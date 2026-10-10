import Foundation

/// Production implementations must authenticate membership, retain troll authorship server-side
/// only, enforce every subject's consent, and reject expired stories on every write.
public protocol FeedRepository: Sendable {
    func fetch() async throws -> CircleSnapshot
    func setConsent(userID: String, allowed: Bool) async throws
    func togglePostLike(id: UUID) async throws -> Post
    func addComment(postID: UUID, text: String) async throws -> Post
    func editPost(id: UUID, caption: String) async throws -> Post
    func deletePost(id: UUID) async throws
    func postLikes(id: UUID) async throws -> [User]
    func createPost(media: CircleMedia, caption: String) async throws -> Post
    func createStory(media: CircleMedia, caption: String) async throws -> Story
    func markStorySeen(id: UUID) async throws
    func toggleStoryLike(id: UUID) async throws
    func reply(storyID: UUID, text: String) async throws
    func createTrollPost(media: CircleMedia, caption: String, subjectIDs: Set<String>) async throws -> TrollPost
    func reactToTroll(id: UUID) async throws -> TrollPost
    func reportTroll(id: UUID, reason: String) async throws
}

public actor MockFeedRepository: FeedRepository {
    private var snapshot: CircleSnapshot
    private var reports: [UUID: String] = [:]
    private var replies: [UUID: [String]] = [:]
    public init(snapshot: CircleSnapshot = MockData.snapshot()) { self.snapshot = snapshot }
    public func fetch() -> CircleSnapshot { snapshot }
    public func setConsent(userID: String, allowed: Bool) {
        if let i = snapshot.friends.firstIndex(where: { $0.id == userID }) {
            snapshot.friends[i].allowsTrollPosts = allowed
        }
    }
    public func togglePostLike(id: UUID) throws -> Post {
        guard let i = snapshot.posts.firstIndex(where: { $0.id == id }) else { throw CircleRepositoryError.notFound }
        snapshot.posts[i].isLiked.toggle()
        snapshot.posts[i].likes += snapshot.posts[i].isLiked ? 1 : -1
        return snapshot.posts[i]
    }
    public func addComment(postID: UUID, text: String) throws -> Post {
        guard let i = snapshot.posts.firstIndex(where: { $0.id == postID }) else { throw CircleRepositoryError.notFound }
        snapshot.posts[i].comments.append(text)
        return snapshot.posts[i]
    }
    public func editPost(id: UUID, caption: String) throws -> Post {
        guard let i = snapshot.posts.firstIndex(where: { $0.id == id }) else { throw CircleRepositoryError.notFound }; snapshot.posts[i].caption = caption; return snapshot.posts[i]
    }
    public func deletePost(id: UUID) { snapshot.posts.removeAll { $0.id == id } }
    public func postLikes(id: UUID) -> [User] { [] }
    public func createPost(media: CircleMedia, caption: String) throws -> Post {
        try validate(media)
        let post = Post(id: UUID(), author: snapshot.friends[0], media: [media], caption: caption,
                        createdAt: .now, likes: 0, comments: [], isLiked: false)
        snapshot.posts.insert(post, at: 0)
        return post
    }
    public func createStory(media: CircleMedia, caption: String) throws -> Story {
        try validate(media)
        let story = Story(id: UUID(), user: snapshot.friends[0], media: media, caption: caption,
                          createdAt: .now, expiresAt: Date.now.addingTimeInterval(86400), isSeen: false, isLiked: false)
        snapshot.stories.insert(story, at: 0)
        return story
    }
    private func storyIndex(_ id: UUID) throws -> Int {
        guard let i = snapshot.stories.firstIndex(where: { $0.id == id }) else { throw CircleRepositoryError.notFound }
        guard snapshot.stories[i].isActive(at: .now) else { throw CircleRepositoryError.expiredStory }
        return i
    }
    public func markStorySeen(id: UUID) throws { let i = try storyIndex(id); snapshot.stories[i].isSeen = true }
    public func toggleStoryLike(id: UUID) throws { let i = try storyIndex(id); snapshot.stories[i].isLiked.toggle() }
    public func reply(storyID: UUID, text: String) throws {
        _ = try storyIndex(storyID); replies[storyID, default: []].append(text)
    }
    public func createTrollPost(media: CircleMedia, caption: String, subjectIDs: Set<String>) throws -> TrollPost {
        try validate(media)
        guard !subjectIDs.isEmpty else { throw CircleRepositoryError.missingSubjects }
        guard subjectIDs.allSatisfy({ id in snapshot.friends.contains { $0.id == id && $0.allowsTrollPosts } }) else {
            throw CircleRepositoryError.optedOut
        }
        let post = TrollPost(id: UUID(), imageURL: media.url, imageData: media.imageData, caption: caption,
                             createdAt: .now, reactions: 0, hasReacted: false, aspectRatio: 0.78)
        snapshot.trollPosts.insert(post, at: 0)
        return post
    }
    public func reactToTroll(id: UUID) throws -> TrollPost {
        guard let i = snapshot.trollPosts.firstIndex(where: { $0.id == id }) else { throw CircleRepositoryError.notFound }
        snapshot.trollPosts[i].hasReacted.toggle()
        snapshot.trollPosts[i].reactions += snapshot.trollPosts[i].hasReacted ? 1 : -1
        return snapshot.trollPosts[i]
    }
    public func reportTroll(id: UUID, reason: String) throws {
        guard snapshot.trollPosts.contains(where: { $0.id == id }) else { throw CircleRepositoryError.notFound }
        reports[id] = reason
        snapshot.trollPosts.removeAll { $0.id == id }
    }
    private func validate(_ media: CircleMedia) throws {
        guard media.url != nil || media.imageData?.isEmpty == false else { throw CircleRepositoryError.emptyMedia }
    }
}
