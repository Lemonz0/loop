import SwiftUI

/// Shared application environment dependencies and server configuration.
@Observable
@MainActor
public final class AppEnvironment {
    public static let shared = AppEnvironment()
    
    private static let serverAddressKey = "settings_server_address"
    
    public var serverAddress: String {
        get {
            UserDefaults.standard.string(forKey: Self.serverAddressKey) ?? "http://192.168.1.132:8080"
        }
        set {
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(cleaned, forKey: Self.serverAddressKey)
        }
    }
    
    public var serverBaseURL: URL {
        let cleaned = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty, let url = URL(string: cleaned) {
            return url
        }
        return URL(string: "http://192.168.1.132:8080")!
    }
    
    public var serverWSURL: URL {
        let base = serverBaseURL.absoluteString
        var wsString: String
        if base.hasPrefix("https://") {
            wsString = base.replacingOccurrences(of: "https://", with: "wss://")
        } else if base.hasPrefix("http://") {
            wsString = base.replacingOccurrences(of: "http://", with: "ws://")
        } else {
            wsString = "ws://" + base
        }
        if wsString.hasSuffix("/") {
            wsString = String(wsString.dropLast())
        }
        return URL(string: wsString + "/ws") ?? URL(string: "ws://192.168.1.132:8080/ws")!
    }
    
    public let chatStore = ChatStore()
    public let authManager = AuthSessionManager.shared
    public let mediaUploadManager = MediaUploadManager.shared
    public let callManager = WebRTCManager.shared
    
    private init() {}
    
    /// Establishes connection when session is active.
    public func activateSessionIfAvailable() {
        if authManager.isAuthenticated, let session = authManager.currentSession {
            chatStore.configure(circles: authManager.circles)
            chatStore.start(serverWSURL: serverWSURL, token: session.token, user: session.user)
        }
    }
    
    /// Reconnects with updated server address.
    public func reconnectServer() {
        if let session = authManager.currentSession {
            Task {
                if await authManager.validateSavedSession(serverURL: serverBaseURL) {
                    chatStore.configure(circles: authManager.circles)
                    chatStore.reconnect(serverWSURL: serverWSURL, token: session.token, user: session.user)
                }
            }
        }
    }
}
