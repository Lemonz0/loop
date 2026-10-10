import Foundation

public actor RemoteFeedRepository: FeedRepository {
    private let token: String
    private let baseURL: URL
    private let circleID: String
    private let userID: String
    public init(token: String, baseURL: URL, circleID: String, userID: String) {
        self.token = token; self.baseURL = baseURL; self.circleID = circleID; self.userID = userID
    }
    private var prefix: String { "api/circles/\(circleID)/social" }
    private func call<T: Decodable & Sendable>(_ suffix: String, body: Data? = nil, as type: T.Type) async throws -> T {
        try await AccountHTTPClient.shared.request(prefix + suffix, baseURL: baseURL, token: token, body: body, as: type)
    }
    public func fetch() async throws -> CircleSnapshot { try await call("", as: CircleSnapshot.self) }
    public func setConsent(userID: String, allowed: Bool) async throws {
        guard userID == self.userID else { throw CircleRepositoryError.notFound }
        struct Body: Encodable { let allowed: Bool }
        struct Result: Decodable, Sendable { let success: Bool }
        _ = try await AccountHTTPClient.shared.request("api/social/consent", baseURL: baseURL, token: token,
            body: JSONEncoder().encode(Body(allowed: allowed)), as: Result.self)
    }
    public func togglePostLike(id: UUID) async throws -> Post { try await call("/posts/\(id.uuidString.lowercased())/like", body: Data("{}".utf8), as: Post.self) }
    public func addComment(postID: UUID, text: String) async throws -> Post {
        struct Body: Encodable { let text: String }
        return try await call("/posts/\(postID.uuidString.lowercased())/comments", body: JSONEncoder().encode(Body(text: text)), as: Post.self)
    }
    public func editPost(id: UUID, caption: String) async throws -> Post {
        struct Body: Encodable { let caption: String }
        return try await call("/posts/\(id.uuidString.lowercased())/edit", body: JSONEncoder().encode(Body(caption: caption)), as: Post.self)
    }
    public func deletePost(id: UUID) async throws {
        struct Result: Decodable, Sendable { let success: Bool }
        _ = try await call("/posts/\(id.uuidString.lowercased())/delete", body: Data("{}".utf8), as: Result.self)
    }
    public func postLikes(id: UUID) async throws -> [User] {
        struct Result: Decodable, Sendable { let users: [User] }
        return try await call("/posts/\(id.uuidString.lowercased())/likes", as: Result.self).users
    }
    private func publish<T: Decodable & Sendable>(_ kind: String, media: CircleMedia, caption: String, subjects: Set<String> = [], as type: T.Type) async throws -> T {
        guard let data = media.imageData, !data.isEmpty else { throw CircleRepositoryError.emptyMedia }
        let photo = try await AccountHTTPClient.shared.uploadSocialPhoto(data, baseURL: baseURL, token: token, circleID: circleID)
        return try await call("/" + kind, body: JSONEncoder().encode(SocialCreateRequest(imageURL: photo, caption: caption, subjectIDs: Array(subjects))), as: type)
    }
    public func createPost(media: CircleMedia, caption: String) async throws -> Post { try await publish("posts", media: media, caption: caption, as: Post.self) }
    public func createStory(media: CircleMedia, caption: String) async throws -> Story { try await publish("stories", media: media, caption: caption, as: Story.self) }
    public func createTrollPost(media: CircleMedia, caption: String, subjectIDs: Set<String>) async throws -> TrollPost { try await publish("trolls", media: media, caption: caption, subjects: subjectIDs, as: TrollPost.self) }
    public func reactToTroll(id: UUID) async throws -> TrollPost { try await call("/trolls/\(id.uuidString.lowercased())/react", body: Data("{}".utf8), as: TrollPost.self) }
    public func markStorySeen(id: UUID) async throws { try await storyAction(id, action: "seen") }
    public func toggleStoryLike(id: UUID) async throws { try await storyAction(id, action: "like") }
    public func reply(storyID: UUID, text: String) async throws { try await storyAction(storyID, action: "replies", text: text) }
    private func storyAction(_ id: UUID, action: String, text: String? = nil) async throws {
        struct Body: Encodable { let text: String? }
        struct Result: Decodable, Sendable { let success: Bool }
        _ = try await call("/stories/\(id.uuidString.lowercased())/\(action)", body: JSONEncoder().encode(Body(text: text)), as: Result.self)
    }
    public func reportTroll(id: UUID, reason: String) async throws {
        struct Body: Encodable { let reason: String }
        struct Result: Decodable, Sendable { let success: Bool }
        _ = try await call("/trolls/\(id.uuidString.lowercased())/report", body: JSONEncoder().encode(Body(reason: reason)), as: Result.self)
    }
}
private struct SocialCreateRequest: Encodable { let imageURL: String; let caption: String; let subjectIDs: [String] }
