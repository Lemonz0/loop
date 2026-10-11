import Foundation
import SwiftUI
import UIKit
import UserNotifications

@Observable @MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private(set) var permission: UNAuthorizationStatus = .notDetermined
    private(set) var remoteRegistered = false
    private(set) var status = "Alerts while Loop is running."
    private(set) var testStatus: String?
    private(set) var isSendingTest = false
    var pendingRoomID: String?
    var pendingUserID: String?
    private var deviceToken: String?
    private var generation = 0
    private let center = UNUserNotificationCenter.current()
    private var enabled: Bool { UserDefaults.standard.object(forKey: "settings_push_enabled") as? Bool ?? true }
    private var sounds: Bool { UserDefaults.standard.object(forKey: "settings_in_app_sounds") as? Bool ?? true }
    override private init() { super.init(); center.delegate = self }

    func configure() async {
        generation += 1
        let attempt = generation
        guard AuthSessionManager.shared.isAuthenticated else { return }
        do {
            if enabled { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
            await refreshPermission()
            guard generation == attempt else { return }
            if !enabled {
                remoteRegistered = false
                center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications()
                UIApplication.shared.unregisterForRemoteNotifications()
                status = "Notifications are off."
                try? await unregister()
                return
            }
            guard permission == .authorized || permission == .provisional else {
                remoteRegistered = false
                UIApplication.shared.unregisterForRemoteNotifications()
                status = "Allow notifications in iOS Settings."
                try? await unregister()
                return
            }
            guard let environment = pushEnvironment else { status = "Local alerts enabled. This signing profile does not support background push."; return }
            let auth = AuthSessionManager.shared
            guard let token = auth.currentSession?.token, let base = auth.savedServerURL else { return }
            struct Status: Decodable, Sendable { let available: Bool }
            let result = try await AccountHTTPClient.shared.request("api/push/status", baseURL: base, token: token, as: Status.self)
            guard generation == attempt, auth.currentSession?.token == token else { return }
            guard result.available else { remoteRegistered = false; status = "Local alerts enabled. Server APNs credentials are not configured yet."; return }
            if deviceToken != nil { await register(environment: environment) }
            else { status = "Registering with Apple…"; UIApplication.shared.registerForRemoteNotifications() }
        } catch { if generation == attempt { status = "Local alerts enabled. Push setup could not reach the server." } }
    }
    func refreshPermission() async { permission = await center.notificationSettings().authorizationStatus }
    func receivedToken(_ data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        if let environment = pushEnvironment { Task { await register(environment: environment) } }
    }
    func registrationFailed() { remoteRegistered = false; status = "Local alerts enabled. Background push requires a push-enabled signing profile." }
    private func register(environment: String) async {
        let auth = AuthSessionManager.shared, attempt = generation
        guard enabled, let token = auth.currentSession?.token, let base = auth.savedServerURL, let deviceToken, let topic = Bundle.main.bundleIdentifier else { return }
        struct Body: Encodable { let deviceToken: String; let topic: String; let environment: String; let sound: Bool }
        struct Result: Decodable, Sendable { let available: Bool; let registered: Bool }
        do {
            let result = try await AccountHTTPClient.shared.request("api/push/register", baseURL: base, token: token,
                body: JSONEncoder().encode(Body(deviceToken: deviceToken, topic: topic, environment: environment, sound: sounds)), as: Result.self)
            guard generation == attempt, enabled, auth.currentSession?.token == token else { return }
            remoteRegistered = result.registered; status = result.registered ? "Background message notifications enabled." : "Local alerts enabled. Server APNs credentials are not configured yet."
        } catch { if generation == attempt { registrationFailed() } }
    }
    private func unregister() async throws {
        let auth = AuthSessionManager.shared
        guard let token = auth.currentSession?.token, let base = auth.savedServerURL else { return }
        struct Result: Decodable, Sendable { let success: Bool }
        _ = try await AccountHTTPClient.shared.request("api/push/unregister", baseURL: base, token: token, body: Data("{}".utf8), as: Result.self)
    }
    func reset() {
        testStatus = nil
        generation += 1; remoteRegistered = false; pendingRoomID = nil; pendingUserID = nil
        center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications()
        UIApplication.shared.unregisterForRemoteNotifications()
        Task { try? await center.setBadgeCount(0) }
    }
    func received(_ message: ChatMessage) {
        guard enabled, !message.isFromCurrentUser, !remoteRegistered,
              let user = AuthSessionManager.shared.currentSession?.user.id else { return }
        let content = UNMutableNotificationContent()
        content.title = "Loop"; content.body = "You have a new message."
        content.threadIdentifier = message.roomId
        content.userInfo = ["roomId": message.roomId, "messageId": message.id, "userId": user]
        if sounds { content.sound = .default }
        let request = UNNotificationRequest(identifier: "message-" + message.id, content: content, trigger: nil)
        center.add(request) { _ in }
    }

    func sendTestAlert() async {
        guard !isSendingTest else { return }
        isSendingTest = true; testStatus = nil
        defer { isSendingTest = false }
        await configure()
        let auth = AuthSessionManager.shared, attempt = generation
        guard enabled else { testStatus = "Turn on message notifications first."; return }
        guard auth.isAuthenticated, let user = auth.currentSession?.user.id else { return }
        guard permission == .authorized || permission == .provisional else {
            testStatus = "Allow notifications in iOS Settings, then try again."; return
        }
        let content = UNMutableNotificationContent()
        content.title = "Loop"; content.body = "Your test notification is working."
        content.userInfo = ["userId": user, "kind": "test"]
        if sounds { content.sound = .default }
        do {
            try await center.add(UNNotificationRequest(identifier: "loop-test", content: content, trigger: nil))
            guard generation == attempt, auth.currentSession?.user.id == user else {
                center.removePendingNotificationRequests(withIdentifiers: ["loop-test"])
                center.removeDeliveredNotifications(withIdentifiers: ["loop-test"])
                return
            }
            testStatus = "Test alert sent. This checks local alerts; background push status is shown above."
        } catch {
            if generation == attempt { testStatus = "Could not send a test alert. Check iOS notification settings." }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let room = notification.request.content.userInfo["roomId"] as? String
        let user = notification.request.content.userInfo["userId"] as? String
        return await MainActor.run {
            guard self.enabled, AuthSessionManager.shared.isAuthenticated, let user, user == AuthSessionManager.shared.currentSession?.user.id else { return [] }
            if let room, AppEnvironment.shared.chatStore.activeRoom?.id == room { return self.sounds ? [.sound] : [] }
            return self.sounds ? [.banner, .list, .sound] : [.banner, .list]
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let room = response.notification.request.content.userInfo["roomId"] as? String
        let user = response.notification.request.content.userInfo["userId"] as? String
        await MainActor.run {
            guard let user, let room else { return }
            // Cold-launch taps arrive before the server-bound session is validated.
            // The tab host checks the recipient after authentication finishes.
            self.pendingUserID = user; self.pendingRoomID = room
        }
    }
    // Re-signing may add or remove push capability. Read the actual embedded profile.
    private var pushEnvironment: String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex),
              let xml = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let profile = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any], let value = entitlements["aps-environment"] as? String,
              value == "development" || value == "production" else { return nil }
        return value
    }
}

@MainActor
final class LoopAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = NotificationManager.shared
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { NotificationManager.shared.receivedToken(deviceToken) }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { NotificationManager.shared.registrationFailed() }
}
