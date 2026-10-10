import XCTest

final class CircleRepositoryTests: XCTestCase {
    func testTrollPayloadHasNoAuthorship() throws {
        let post = MockData.snapshot().trollPosts[0]
        let data = try JSONEncoder().encode(post)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["author"])
        XCTAssertNil(object["authorID"])
        XCTAssertNil(object["uploaderID"])
    }
    func testConsentIsEnforcedByRepository() async throws {
        let repository = MockFeedRepository()
        await repository.setConsent(userID: "maya", allowed: false)
        do {
            _ = try await repository.createTrollPost(media: CircleMedia(imageData: Data([1])), caption: "Test", subjectIDs: ["maya"])
            XCTFail("Opted-out subjects must be rejected")
        } catch CircleRepositoryError.optedOut {}
        await repository.setConsent(userID: "maya", allowed: true)
        let posted = try await repository.createTrollPost(media: CircleMedia(imageData: Data([1])), caption: "Test", subjectIDs: ["maya"])
        let snapshot = await repository.fetch()
        XCTAssertEqual(snapshot.trollPosts.first?.id, posted.id)
    }
    func testEmptySubjectsRejected() async throws {
        let repository = MockFeedRepository()
        do {
            _ = try await repository.createTrollPost(media: CircleMedia(imageData: Data([1])), caption: "Test", subjectIDs: [])
            XCTFail("Subjects are required for consent checks")
        } catch CircleRepositoryError.missingSubjects {}
    }
    func testReactionCanBeToggledWithoutCountDrift() async throws {
        let repository = MockFeedRepository()
        let initial = await repository.fetch().trollPosts[0]
        let liked = try await repository.reactToTroll(id: initial.id)
        XCTAssertEqual(liked.reactions, initial.reactions + 1)
        let unliked = try await repository.reactToTroll(id: initial.id)
        XCTAssertEqual(unliked.reactions, initial.reactions)
        XCTAssertFalse(unliked.hasReacted)
    }
    func testExpiredStoriesRejectReplies() async throws {
        let snapshot = MockData.snapshot(now: Date.now.addingTimeInterval(-2 * 86400))
        let repository = MockFeedRepository(snapshot: snapshot)
        do {
            try await repository.reply(storyID: snapshot.stories[0].id, text: "Too late")
            XCTFail("Expired stories must not accept writes")
        } catch CircleRepositoryError.expiredStory {}
    }
    func testCreatedStoryHas24HourLifetime() async throws {
        let repository = MockFeedRepository()
        let story = try await repository.createStory(media: CircleMedia(imageData: Data([1])), caption: "Test")
        XCTAssertEqual(story.expiresAt.timeIntervalSince(story.createdAt), 86400, accuracy: 1)
        XCTAssertFalse(story.isActive(at: story.expiresAt))
    }
    @MainActor
    func testStoryPausesAndAdvances() {
        let snapshot = MockData.snapshot()
        let viewer = StoryViewerModel(stories: snapshot.stories, startingAt: snapshot.stories[0].id, repository: MockFeedRepository(snapshot: snapshot))
        let now = Date.now
        viewer.isHeld = true
        viewer.tick(now: now.addingTimeInterval(1), isForeground: true)
        XCTAssertEqual(viewer.elapsed, 0)
        viewer.isHeld = false
        viewer.isReplying = true
        viewer.tick(now: now.addingTimeInterval(2), isForeground: true)
        XCTAssertEqual(viewer.elapsed, 0)
        viewer.isReplying = false
        for i in 1...12 { viewer.tick(now: now.addingTimeInterval(2 + Double(i) * 0.5), isForeground: true) }
        XCTAssertEqual(viewer.index, 1)
        viewer.previous()
        XCTAssertEqual(viewer.index, 0)
    }
    @MainActor
    func testExpiredViewerDismisses() {
        let snapshot = MockData.snapshot(now: Date.now.addingTimeInterval(-2 * 86400))
        let viewer = StoryViewerModel(stories: snapshot.stories, startingAt: snapshot.stories[0].id, repository: MockFeedRepository(snapshot: snapshot))
        viewer.tick(isForeground: true)
        XCTAssertTrue(viewer.shouldDismiss)
    }
}
