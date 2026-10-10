import XCTest
import Foundation

final class ProfileCodecTests: XCTestCase {
    func testPrivateCardDecodesWithoutSensitiveFields() throws {
        let json = #"{"user":{"id":"friend","username":"","displayName":"Friend"},"isSelf":false,"state":"private","kind":"person","verified":false,"personal":{"nickname":"","note":"","contact":false,"blocked":false,"muted":false,"requested":true,"disappearingSeconds":0},"presenceVisible":false,"mutualGroups":[],"mutualContacts":[],"links":[],"canCall":false,"canMessage":false}"#
        let card = try AccountCodec.decoder().decode(PersonCard.self, from: Data(json.utf8))
        XCTAssertNil(card.presence)
        XCTAssertNil(card.bio)
        XCTAssertNil(card.sharedItems)
        XCTAssertTrue(card.personal.requested)
        XCTAssertFalse(card.canMessage)
    }
    func testProfileDatesAndReplyIdentitySurviveServerPayload() throws {
        let json = #"{"user":{"id":"friend","username":"friend","displayName":"Friend"},"isSelf":false,"state":"active","kind":"person","verified":true,"personal":{"nickname":"Friend","note":"Only me","contact":true,"blocked":false,"muted":false,"requested":false,"disappearingSeconds":86400},"memberSince":"2025-03-12T16:42:00.123Z","presenceVisible":true,"presence":{"userId":"friend","displayName":"Friend","isOnline":true,"lastSeen":"2026-10-10T12:00:00.000Z"},"mutualGroups":[],"mutualContacts":[],"links":[],"canCall":true,"canMessage":true,"sharedItems":[{"id":"reply","roomId":"room","senderId":"friend","senderName":"Friend","content":"https://example.com","timestamp":"2026-10-10T12:00:00.000Z","status":"sent","replyToId":"original","reactions":[{"userId":"owner","emoji":"👍"}]}]}"#
        let card = try AccountCodec.decoder().decode(PersonCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.memberSince?.timeIntervalSince1970 ?? 0, 1741797720.123, accuracy: 0.001)
        XCTAssertEqual(card.sharedItems?.first?.replyToId, "original")
        XCTAssertEqual(card.sharedItems?.first?.reactions?.first?.userId, "owner")
        XCTAssertEqual(card.presence?.isOnline, true)
    }
}
