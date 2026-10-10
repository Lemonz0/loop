import Foundation
import Security

@Observable @MainActor
public final class AuthSessionManager {
    public static let shared = AuthSessionManager()
    public private(set) var currentSession: AuthSession?
    public private(set) var circles: [AccountCircle] = []
    public private(set) var isAuthenticated = false
    public private(set) var isValidating = false
    public private(set) var isAuthenticating = false
    public var lastError: String?
    public private(set) var savedServerURL: URL?
    private let keychainService = "com.liquidglass.messaging.auth"
    private let sessionKey = "user_session_v1"
    private var generation = 0
    private var privateMediaFiles: Set<URL> = []
    public init() {
        if let stored = loadStoredSession(), AccountCodec.valid(stored) {
            currentSession = stored.session; savedServerURL = stored.serverURL; isValidating = true
        } else { clearStoredSession() }
    }
    public func signIn(username: String, password: String, invite: String? = nil, displayName: String = "", serverURL: URL) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true; lastError = nil
        defer { isAuthenticating = false }
        generation += 1; let attempt = generation
        do {
            let body: Data
            let route: String
            if let invite {
                body = try JSONEncoder().encode(InviteAuthRequest(secretKey: invite, chosenDisplayName: displayName, username: username, password: password))
                route = "api/auth/invite"
            } else {
                body = try JSONEncoder().encode(AccountLoginRequest(username: username, password: password)); route = "api/auth/login"
            }
            let response = try await AccountHTTPClient.shared.request(route, baseURL: serverURL, body: body, as: InviteAuthResponse.self)
            guard generation == attempt else { return false }
            guard response.success, let session = response.session else { throw AccountHTTPError(status: 401, message: response.errorMessage ?? "Could not authenticate.") }
            let stored = StoredAccountSession(session: session, serverURL: serverURL)
            guard AccountCodec.valid(stored) else { throw AccountHTTPError(status: 401, message: "The server returned an invalid session.") }
            try saveSession(stored)
            currentSession = session; savedServerURL = serverURL
            return await validateSavedSession(serverURL: serverURL)
        } catch { if generation == attempt { lastError = error.localizedDescription }; return false }
    }
    @discardableResult public func validateSavedSession(serverURL: URL) async -> Bool {
        guard let session = currentSession, savedServerURL == serverURL else {
            isValidating = false; isAuthenticated = false; return false
        }
        isValidating = true; lastError = nil
        let attempt = generation
        defer { isValidating = false }
        do {
            let response = try await AccountHTTPClient.shared.request("api/auth/me", baseURL: serverURL, token: session.token, as: AccountProfileResponse.self)
            guard generation == attempt else { return false }
            var refreshed = session; refreshed.user = response.user
            try saveSession(StoredAccountSession(session: refreshed, serverURL: serverURL))
            currentSession = refreshed; circles = response.circles; isAuthenticated = true; return true
        } catch {
            guard generation == attempt else { return false }
            if let error = error as? AccountHTTPError, error.status == 401 { discardSession() }
            isAuthenticated = false; lastError = error.localizedDescription; return false
        }
    }
    public func createCircle(name: String) async -> Bool {
        guard let session = currentSession, let url = savedServerURL, isAuthenticated else { return false }
        struct Body: Encodable { let name: String }
        struct Response: Decodable, Sendable { let circle: AccountCircle }
        do {
            lastError = nil
            let result = try await AccountHTTPClient.shared.request("api/circles", baseURL: url, token: session.token,
                body: JSONEncoder().encode(Body(name: name)), as: Response.self)
            guard currentSession?.token == session.token else { return false }
            circles.removeAll { $0.id == result.circle.id }; circles.append(result.circle)
            AppEnvironment.shared.chatStore.configure(circles: circles)
            await AppEnvironment.shared.chatStore.refreshRooms()
            return true
        } catch { lastError = error.localizedDescription; return false }
    }
    public func joinCircle(code: String) async -> Bool {
        guard let session = currentSession, let url = savedServerURL, isAuthenticated else { return false }
        struct Body: Encodable { let secretKey: String }
        struct Response: Decodable, Sendable { let circle: AccountCircle }
        do {
            _ = try await AccountHTTPClient.shared.request("api/invites/join", baseURL: url, token: session.token,
                body: JSONEncoder().encode(Body(secretKey: code)), as: Response.self)
            return await validateSavedSession(serverURL: url)
        } catch { lastError = error.localizedDescription; return false }
    }
    public func renameCircle(id: String, name: String) async {
        guard let session = currentSession, let url = savedServerURL, isAuthenticated else { return }
        struct Body: Encodable { let name: String }
        struct Response: Decodable, Sendable { let circle: AccountCircle }
        do {
            _ = try await AccountHTTPClient.shared.request("api/circles/\(id)/rename", baseURL: url, token: session.token,
                body: JSONEncoder().encode(Body(name: name)), as: Response.self)
            _ = await validateSavedSession(serverURL: url)
            AppEnvironment.shared.chatStore.configure(circles: circles)
        } catch { lastError = error.localizedDescription }
    }
    public func createInvite(circleID: String) async -> AccountInvite? {
        guard let session = currentSession, let url = savedServerURL, isAuthenticated else { return nil }
        do { return try await AccountHTTPClient.shared.request("api/circles/\(circleID)/invites", baseURL: url,
            token: session.token, body: Data("{}".utf8), as: AccountInvite.self) }
        catch { lastError = error.localizedDescription; return nil }
    }
    public func updateProfile(displayName: String, avatarURL: URL? = nil) {
        guard let session = currentSession, let url = savedServerURL, isAuthenticated else { return }
        let attempt = generation
        Task {
            struct Body: Encodable { let displayName: String; let avatarURL: String? }
            struct Response: Decodable, Sendable { let user: UserProfile }
            do {
                let result = try await AccountHTTPClient.shared.request("api/auth/profile", baseURL: url, token: session.token,
                    body: JSONEncoder().encode(Body(displayName: displayName, avatarURL: avatarURL?.absoluteString)), as: Response.self)
                guard generation == attempt else { return }
                var updated = session; updated.user = result.user
                try saveSession(StoredAccountSession(session: updated, serverURL: url)); currentSession = updated
            } catch { if generation == attempt { lastError = error.localizedDescription } }
        }
    }
    public func signOut() {
        let token = currentSession?.token, url = savedServerURL
        discardSession()
        if let token, let url {
            Task {
                struct Result: Decodable, Sendable { let success: Bool }
                do { _ = try await AccountHTTPClient.shared.request("api/auth/logout", baseURL: url, token: token,
                    body: Data("{}".utf8), as: Result.self) }
                catch { /* Local sign-out completes even if the server is offline. */ }
            }
        }
    }
    public func mediaFile(_ url: URL) async throws -> URL {
        guard isAuthenticated, let session = currentSession, let base = savedServerURL else { throw URLError(.userAuthenticationRequired) }
        let file = try await AccountHTTPClient.shared.downloadMedia(url, baseURL: base, token: session.token)
        guard isAuthenticated, currentSession?.token == session.token else {
            try? FileManager.default.removeItem(at: file); throw URLError(.userAuthenticationRequired)
        }
        privateMediaFiles.insert(file); return file
    }
    public func discardSession() {
        NotificationManager.shared.reset()
        SpotifyConnectionManager.shared.cancel()
        ProfileRepository.shared.reset(); ProfilePresentation.shared.reset()
        for file in privateMediaFiles { try? FileManager.default.removeItem(at: file) }
        privateMediaFiles = []
        generation += 1; currentSession = nil; savedServerURL = nil; circles = []; isAuthenticated = false
        clearStoredSession()
    }
    private func saveSession(_ stored: StoredAccountSession) throws {
        let data = try JSONEncoder().encode(stored)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: sessionKey]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw URLError(.cannotWriteToFile) }
        } else if update != errSecSuccess { throw URLError(.cannotWriteToFile) }
    }
    private func loadStoredSession() -> StoredAccountSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sessionKey, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredAccountSession.self, from: data)
    }
    private func clearStoredSession() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: sessionKey]
        SecItemDelete(query as CFDictionary)
    }
}
