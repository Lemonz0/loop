import XCTest

final class SocialContractTests: XCTestCase {
    func testPostCommentProfilesDecodeAndLegacyPostsRemainReadable() throws {
        let json = """
        {"id":"00000000-0000-4000-8000-000000000003","author":{"id":"u1","name":"Maya","allowsTrollPosts":true},"media":[],"caption":"Today","createdAt":"2026-10-09T12:00:00.000Z","likes":1,"comments":["Hi"],"isLiked":false,"commentDetails":[{"author":{"id":"u2","name":"Dan","avatarURL":"/uploads/avatar.jpg","allowsTrollPosts":true},"text":"Hi"}]}
        """
        let post = try AccountCodec.decoder().decode(Post.self, from: Data(json.utf8))
        XCTAssertEqual(post.commentDetails?.first?.author.name, "Dan")
        XCTAssertEqual(post.commentDetails?.first?.author.avatarURL?.path, "/uploads/avatar.jpg")
        XCTAssertEqual(post.commentDetails?.first?.text, post.comments.first)
        var legacy = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        legacy.removeValue(forKey: "commentDetails")
        let oldPost = try AccountCodec.decoder().decode(Post.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(oldPost.comments, ["Hi"])
        XCTAssertNil(oldPost.commentDetails)
    }
    func testLiveSnapshotDecodesPrivateRelativeMediaAndOwnConsent() throws {
        let json = """
        {"friends":[{"id":"u1","name":"Maya","allowsTrollPosts":false}],"posts":[],"stories":[{"id":"00000000-0000-4000-8000-000000000001","user":{"id":"u1","name":"Maya","allowsTrollPosts":false},"media":{"url":"/uploads/photo.jpg"},"caption":"Today","createdAt":"2026-10-09T12:00:00.000Z","expiresAt":"2026-10-10T12:00:00.000Z","isSeen":false,"isLiked":false}],"trollPosts":[{"id":"00000000-0000-4000-8000-000000000002","imageURL":"/uploads/anonymous.jpg","caption":"Funny","createdAt":"2026-10-09T12:00:00.000Z","reactions":8,"hasReacted":false,"aspectRatio":0.8}]}
        """
        let snapshot = try AccountCodec.decoder().decode(CircleSnapshot.self, from: Data(json.utf8))
        XCTAssertFalse(snapshot.friends[0].allowsTrollPosts)
        XCTAssertEqual(snapshot.stories[0].media.url?.path, "/uploads/photo.jpg")
        XCTAssertEqual(snapshot.stories[0].expiresAt.timeIntervalSince(snapshot.stories[0].createdAt), 86400)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.trollPosts[0])) as! [String: Any]
        for key in ["author", "authorId", "moderationAuthorId", "uploaderId"] { XCTAssertNil(encoded[key]) }
    }
    func testPrivateReplyDecodesOnlyExpectedFields() throws {
        let data = Data("""
        {"id":"00000000-0000-4000-8000-000000000001","sender":{"id":"u2","name":"Dan","allowsTrollPosts":true},"text":"Hello","createdAt":"2026-10-09T12:00:00.000Z"}
        """.utf8)
        let reply = try AccountCodec.decoder().decode(PrivateStoryReply.self, from: data)
        XCTAssertEqual(reply.sender.name, "Dan"); XCTAssertEqual(reply.text, "Hello")
    }
}
