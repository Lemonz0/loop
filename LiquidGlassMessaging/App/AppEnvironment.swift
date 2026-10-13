import SwiftUI

/// Shared application environment dependencies and server configuration.
@Observable
@MainActor
public final class AppEnvironment {
    public static let shared = AppEnvironment()
    
    public static let serverURL = URL(string: "https://loop.34.89.181.18.nip.io")!
    
    public var serverBaseURL: URL {
        Self.serverURL
    }
    
    public var serverWSURL: URL {
        var components = URLComponents(url: Self.serverURL, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        components.path = "/ws"
        return components.url!
    }
    
    public let chatStore = ChatStore()
    public let authManager = AuthSessionManager.shared
    public let mediaUploadManager = MediaUploadManager.shared
    public let callManager = WebRTCManager.shared
    
    private init() {
        UserDefaults.standard.removeObject(forKey: "settings_server_address")
    }
    
    /// Establishes connection when session is active.
    public func activateSessionIfAvailable() {
        if authManager.isAuthenticated, let session = authManager.currentSession {
            chatStore.configure(circles: authManager.circles)
            chatStore.start(serverWSURL: serverWSURL, token: session.token, user: session.user)
        }
    }
    
    /// Revalidates the session and reconnects to Loop.
    public func reconnectServer() {
        if let session = authManager.currentSession {
            Task {
                if await authManager.validateSavedSession() {
                    chatStore.configure(circles: authManager.circles)
                    chatStore.reconnect(serverWSURL: serverWSURL, token: session.token, user: session.user)
                }
            }
        }
    }
}
