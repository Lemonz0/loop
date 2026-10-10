import Foundation
import Observation

/// Memory-only cache is scoped to the authenticated session and invalidated by account events.
@Observable @MainActor
final class ProfileRepository {
    static let shared = ProfileRepository()
    private var cache: [String: PersonCard] = [:]
    private var sessionToken: String?
    private var revision = 0
    func reset() { revision += 1; cache = [:]; sessionToken = nil }
    private func key(_ id: String, _ context: ProfileContext) -> String { id + ":" + (context.circleID ?? "") }
    func cached(_ id: String, context: ProfileContext) -> PersonCard? {
        if sessionToken != AuthSessionManager.shared.currentSession?.token { reset(); sessionToken = AuthSessionManager.shared.currentSession?.token }
        return cache[key(id, context)]
    }
    func load(_ id: String, context: ProfileContext) async throws -> PersonCard {
        _ = cached(id, context: context)
        let expected = revision
        var query: [URLQueryItem] = []
        if let circle = context.circleID { query.append(URLQueryItem(name: "circleId", value: circle)) }
        if let room = context.roomID { query.append(URLQueryItem(name: "roomId", value: room)) }
        let card: PersonCard = try await request("api/profiles/\(id)", query: query)
        try Task.checkCancellation()
        guard expected == revision else { throw CancellationError() }
        cache[key(id, context)] = card
        return card
    }
    func perform(_ id: String, action: ProfileAction, context: ProfileContext) async throws -> PersonCard {
        let _: PersonCard = try await request("api/profiles/\(id)/actions", body: JSONEncoder().encode(action))
        cache = cache.filter { !$0.key.hasPrefix(id + ":") }
        return try await load(id, context: context)
    }
    func manage(_ id: String, circleID: String, action: String) async throws {
        struct Body: Encodable { let circleId: String; let action: String }
        struct Result: Decodable, Sendable { let success: Bool }
        let _: Result = try await request("api/profiles/\(id)/group", body: JSONEncoder().encode(Body(circleId: circleID, action: action)))
        reset()
    }
    func request<T: Decodable & Sendable>(_ path: String, body: Data? = nil, query: [URLQueryItem] = []) async throws -> T {
        let auth = AuthSessionManager.shared
        guard auth.isAuthenticated, let session = auth.currentSession, let base = auth.savedServerURL else { throw URLError(.userAuthenticationRequired) }
        let result = try await AccountHTTPClient.shared.request(path, baseURL: base, token: session.token, body: body, query: query, as: T.self)
        guard auth.currentSession?.token == session.token else { throw CancellationError() }
        return result
    }
}
