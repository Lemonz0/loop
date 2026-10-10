import SwiftUI

@Observable @MainActor
public final class CircleViewModel {
    public private(set) var snapshot = MockData.snapshot()
    public var errorMessage: String?
    public private(set) var isLoading = false
    public private(set) var feedback = 0
    public private(set) var consentPending = false
    public private(set) var allowTrollPosts = UserDefaults.standard.object(forKey: "circle_allow_troll_posts") as? Bool ?? true
    @ObservationIgnored public private(set) var repository: any FeedRepository
    @ObservationIgnored private var pendingIDs: Set<UUID> = []
    public private(set) var currentCircleID: String?
    public private(set) var currentUserID = "me"
    public private(set) var isLive = false
    public private(set) var hasLoaded = false
    private var generation = 0
    private var mutationRevision = 0
    public func isPending(_ id: UUID) -> Bool { pendingIDs.contains(id) }
    public init(repository: any FeedRepository = MockFeedRepository()) { self.repository = repository }
    public static func production() -> CircleViewModel {
        let auth = AuthSessionManager.shared
        let id = auth.circles.first?.id ?? ""
        let user = auth.currentSession?.user.id ?? ""
        let model = CircleViewModel(repository: RemoteFeedRepository(token: auth.currentSession?.token ?? "",
            baseURL: auth.savedServerURL ?? AppEnvironment.shared.serverBaseURL, circleID: id, userID: user))
        model.currentCircleID = id; model.currentUserID = user; model.isLive = true
        model.snapshot = CircleSnapshot(friends: [], posts: [], stories: [], trollPosts: [])
        model.allowTrollPosts = false
        return model
    }
    public func selectCircle(_ circleID: String) async {
        guard isLive, let session = AuthSessionManager.shared.currentSession,
              let url = AuthSessionManager.shared.savedServerURL else { return }
        generation += 1; pendingIDs.removeAll(); currentCircleID = circleID; hasLoaded = false; isLoading = false
        snapshot = CircleSnapshot(friends: [], posts: [], stories: [], trollPosts: [])
        repository = RemoteFeedRepository(token: session.token, baseURL: url, circleID: circleID, userID: currentUserID)
        await refresh()
    }
    private func handleError(_ error: Error) {
        if isLive, let http = error as? AccountHTTPError, http.status == 401 { AuthSessionManager.shared.discardSession() }
        errorMessage = error.localizedDescription
    }
    public func activeStories(at now: Date) -> [Story] { snapshot.stories.filter { $0.isActive(at: now) } }
    public func refresh() async {
        guard !isLoading else { return }
        let attempt = generation, revision = mutationRevision
        isLoading = true; defer { if attempt == generation { isLoading = false } }
        do {
            let fetched = try await repository.fetch()
            try Task.checkCancellation()
            guard generation == attempt, revision == mutationRevision else { return }
            let pending = snapshot.posts.filter { pendingIDs.contains($0.id) }
            snapshot = fetched
            for post in pending { if let i = snapshot.posts.firstIndex(where: { $0.id == post.id }) { snapshot.posts[i] = post } }; hasLoaded = true
            allowTrollPosts = snapshot.friends.first(where: { $0.id == currentUserID })?.allowsTrollPosts ?? false
        } catch {
            guard generation == attempt, !Task.isCancelled, !AccountHTTPClient.isCancellation(error) else { return }
            handleError(error)
        }
    }
    public func updateConsent(_ allowed: Bool) async {
        let attempt = generation
        guard !consentPending else { return }
        consentPending = true; defer { consentPending = false }
        do {
            try await repository.setConsent(userID: currentUserID, allowed: allowed)
            guard attempt == generation else { return }
            allowTrollPosts = allowed
            UserDefaults.standard.set(allowed, forKey: "circle_allow_troll_posts")
            snapshot = try await repository.fetch()
        } catch { errorMessage = error.localizedDescription }
    }
    public func like(_ post: Post) async {
        let attempt = generation
        guard !pendingIDs.contains(post.id), let i = snapshot.posts.firstIndex(where: { $0.id == post.id }) else { return }
        let original = snapshot.posts[i]
        pendingIDs.insert(post.id); mutationRevision += 1
        snapshot.posts[i].isLiked.toggle()
        snapshot.posts[i].likes = max(0, original.likes + (original.isLiked ? -1 : 1))
        feedback += 1
        defer { if attempt == generation { pendingIDs.remove(post.id); mutationRevision += 1 } }
        do {
            let updated = try await repository.togglePostLike(id: post.id)
            guard attempt == generation else { return }
            replace(updated)
        } catch { if attempt == generation { replace(original); handleError(error) } }
    }
    @discardableResult public func comment(_ post: Post, text: String) async -> Bool {
        let attempt = generation, text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !pendingIDs.contains(post.id), let i = snapshot.posts.firstIndex(where: { $0.id == post.id }) else { return false }
        let original = snapshot.posts[i]
        pendingIDs.insert(post.id); mutationRevision += 1
        snapshot.posts[i].comments.append(text); feedback += 1
        if let author = snapshot.friends.first(where: { $0.id == currentUserID }), snapshot.posts[i].commentDetails != nil {
            snapshot.posts[i].commentDetails?.append(PostComment(author: author, text: text))
        }
        defer { if attempt == generation { pendingIDs.remove(post.id); mutationRevision += 1 } }
        do {
            let updated = try await repository.addComment(postID: post.id, text: text)
            guard attempt == generation else { return false }; replace(updated); return true
        } catch { if attempt == generation { replace(original); handleError(error) }; return false }
    }
    private func replace(_ post: Post) {
        if let i = snapshot.posts.firstIndex(where: { $0.id == post.id }) { snapshot.posts[i] = post }
    }
    public func edit(_ post: Post, caption: String) async -> Bool {
        let attempt = generation
        guard post.author.id == currentUserID, !pendingIDs.contains(post.id) else { return false }
        pendingIDs.insert(post.id); mutationRevision += 1
        defer { if attempt == generation { pendingIDs.remove(post.id); mutationRevision += 1 } }
        do { let updated = try await repository.editPost(id: post.id, caption: caption); guard attempt == generation else { return false }; replace(updated); return true }
        catch { if attempt == generation { handleError(error) }; return false }
    }
    public func delete(_ post: Post) async {
        let attempt = generation
        guard post.author.id == currentUserID, !pendingIDs.contains(post.id) else { return }
        pendingIDs.insert(post.id); mutationRevision += 1
        defer { if attempt == generation { pendingIDs.remove(post.id); mutationRevision += 1 } }
        do { try await repository.deletePost(id: post.id); guard attempt == generation else { return }; snapshot.posts.removeAll { $0.id == post.id } }
        catch { if attempt == generation { handleError(error) } }
    }
    public func react(_ post: TrollPost) async {
        let attempt = generation
        guard pendingIDs.insert(post.id).inserted else { return }; defer { pendingIDs.remove(post.id) }
        do {
            let updated = try await repository.reactToTroll(id: post.id)
            guard attempt == generation else { return }
            if let i = snapshot.trollPosts.firstIndex(where: { $0.id == post.id }) { snapshot.trollPosts[i] = updated }
            feedback += 1
        } catch { errorMessage = error.localizedDescription }
    }
    public func report(_ post: TrollPost, reason: String) async {
        let attempt = generation
        do {
            try await repository.reportTroll(id: post.id, reason: reason)
            guard attempt == generation else { return }
            snapshot.trollPosts.removeAll { $0.id == post.id }
        } catch { errorMessage = error.localizedDescription }
    }
    public func publish(media: CircleMedia, caption: String, kind: CircleComposerKind, subjects: Set<String>) async -> Bool {
        let attempt = generation
        do {
            switch kind {
            case .post:
                let post = try await repository.createPost(media: media, caption: caption)
                guard attempt == generation else { return false }; snapshot.posts.insert(post, at: 0)
            case .story:
                let story = try await repository.createStory(media: media, caption: caption)
                guard attempt == generation else { return false }; snapshot.stories.insert(story, at: 0)
            case .troll:
                let post = try await repository.createTrollPost(media: media, caption: caption, subjectIDs: subjects)
                guard attempt == generation else { return false }; snapshot.trollPosts.insert(post, at: 0)
            }
            feedback += 1; return true
        } catch { if attempt == generation { handleError(error) }; return false }
    }
}

public enum CircleComposerKind: String, Identifiable, Sendable {
    case post, story, troll
    public var id: String { rawValue }
    public var title: String { self == .troll ? "Post anonymously" : self == .story ? "Add your story" : "Share a post" }
}
