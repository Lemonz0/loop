import AuthenticationServices
import Foundation
import Observation
import UIKit

@Observable @MainActor
final class SpotifyConnectionManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SpotifyConnectionManager()
    private(set) var isConnecting = false
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private var continuation: CheckedContinuation<URL, Error>?
    @ObservationIgnored private var generation = 0
    func connect() async throws {
        guard !isConnecting else { return }
        let auth = AuthSessionManager.shared
        guard let token = auth.currentSession?.token else { throw URLError(.userAuthenticationRequired) }
        isConnecting = true; generation += 1; let attemptGeneration = generation
        defer { if generation == attemptGeneration { isConnecting = false; webSession = nil } }
        do {
            let authorization: SpotifyAuthorization = try await ProfileRepository.shared.request("api/spotify/connect", body: Data("{}".utf8))
            guard auth.currentSession?.token == token, generation == attemptGeneration else { throw CancellationError() }
            guard authorization.authorizationURL.scheme == "https", authorization.authorizationURL.host == "accounts.spotify.com", authorization.authorizationURL.path == "/authorize" else { throw URLError(.badURL) }
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url: authorization.authorizationURL, callbackURLScheme: "loop-spotify") { [weak self] url, error in
                    Task { @MainActor in
                        guard let self, self.generation == attemptGeneration else { return }
                        self.complete(url: url, error: error)
                    }
                }
                session.presentationContextProvider = self
                webSession = session
                if !session.start() { complete(url: nil, error: URLError(.cannotLoadFromNetwork)) }
            }
            guard auth.currentSession?.token == token, generation == attemptGeneration,
                  callback.scheme == "loop-spotify", callback.host == "callback",
                  let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                  parts.queryItems?.first(where: { $0.name == "attempt" })?.value == authorization.attempt else { throw CancellationError() }
            let result = parts.queryItems?.first(where: { $0.name == "result" })?.value
            if result == "denied" { throw CancellationError() }
            guard result == "authorize", let code = parts.queryItems?.first(where: { $0.name == "code" })?.value else { throw AccountHTTPError(status: 400, message: "Spotify could not connect. Check that your account is allowed in the Spotify developer app, then try again.") }
            struct Finish: Encodable { let attempt: String; let code: String }
            let linked: SpotifySettings = try await ProfileRepository.shared.request("api/spotify/finish", body: JSONEncoder().encode(Finish(attempt: authorization.attempt, code: code)))
            guard linked.connected, auth.currentSession?.token == token, generation == attemptGeneration else { throw CancellationError() }
            ProfileRepository.shared.reset()
        } catch {
            if auth.currentSession?.token == token {
                struct Result: Decodable, Sendable { let success: Bool }
                let _: Result? = try? await ProfileRepository.shared.request("api/spotify/cancel", body: Data("{}".utf8))
            }
            throw error
        }
    }
    private func complete(url: URL?, error: Error?) {
        guard let pending = continuation else { return }; continuation = nil
        if let url { pending.resume(returning: url) }
        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { pending.resume(throwing: CancellationError()) }
        else { pending.resume(throwing: error ?? URLError(.cannotLoadFromNetwork)) }
    }
    func cancel() {
        generation += 1; webSession?.cancel(); complete(url: nil, error: CancellationError()); webSession = nil; isConnecting = false
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
