import XCTest

final class AccountContractTests: XCTestCase {
    func testJavaScriptFractionalDatesDecode() throws {
        let json = """
        {"success":true,"session":{"token":"\(String(repeating: "a", count: 43))","user":{"id":"u1","username":"maya","displayName":"Maya"},"issuedAt":"2026-10-09T12:30:00.123Z","expiresAt":"2026-11-08T12:30:00.123Z"}}
        """
        let response = try AccountCodec.decoder().decode(InviteAuthResponse.self, from: Data(json.utf8))
        let session = try XCTUnwrap(response.session)
        XCTAssertEqual(session.expiresAt.timeIntervalSince(session.issuedAt), 30 * 86400, accuracy: 0.01)
    }
    func testFakeAndExpiredSessionsAreRejected() {
        let user = UserProfile(id: "u1", username: "maya", displayName: "Maya")
        let server = URL(string: "http://192.168.1.132:8080")!
        for token in ["local_session_token", "local_dev_123", "tok_123"] {
            XCTAssertFalse(AccountCodec.valid(StoredAccountSession(session: AuthSession(token: token, user: user), serverURL: server)))
        }
        let expired = AuthSession(token: String(repeating: "a", count: 43), user: user, expiresAt: Date().addingTimeInterval(-1))
        XCTAssertFalse(AccountCodec.valid(StoredAccountSession(session: expired, serverURL: server)))
    }
    func testServerURLRejectsPublicHTTPAndEmbeddedCredentials() {
        XCTAssertNotNil(AccountCodec.serverURL("http://192.168.1.132:8080"))
        XCTAssertNotNil(AccountCodec.serverURL("https://loop.example.com"))
        for url in ["http://192.168.1.132.evil.example", "http://example.com", "https://name:password@example.com", "https://example.com?token=secret", "file:///etc/password"] {
            XCTAssertNil(AccountCodec.serverURL(url))
        }
    }
    func testInviteRequestHasPasswordAndUsername() throws {
        let body = InviteAuthRequest(secretKey: "invite", chosenDisplayName: "Maya", username: "maya", password: "a-password-123")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: String])
        XCTAssertEqual(json["username"], "maya"); XCTAssertEqual(json["password"], "a-password-123")
    }
    func testCanonicalBackendMessageDoesNotRequireClientFlag() throws {
        let payload = """
        {"id":"m1","roomId":"r1","senderId":"u1","senderName":"Maya","content":"Hello","timestamp":"2026-10-09T12:30:00.123Z","status":"sent"}
        """
        let message = try AccountCodec.decoder().decode(ChatMessage.self, from: Data(payload.utf8))
        XCTAssertEqual(message.content, "Hello")
        XCTAssertFalse(message.isFromCurrentUser)
    }
    func testDirectRoomPayloadUsesPeerProfileAndPrivateParticipantIDs() throws {
        let json = """
        {"id":"fd11c7f1-3c4c-4562-9de7-2c79a6b8d625","name":"Maya","isGroup":false,"avatarURL":"/uploads/avatar.jpg","participantIds":["u1","u2"],"unreadCount":0,"updatedAt":"2026-10-10T00:00:00.123Z"}
        """
        let room = try AccountCodec.decoder().decode(ChatRoom.self, from: Data(json.utf8))
        XCTAssertFalse(room.isGroup)
        XCTAssertEqual(room.participantIds, ["u1", "u2"])
        XCTAssertEqual(room.avatarURL?.relativeString, "/uploads/avatar.jpg")
        XCTAssertNil(room.lastMessage)
    }

    func testRefreshCancellationDoesNotHideRealNetworkFailures() {
        XCTAssertTrue(AccountHTTPClient.isCancellation(CancellationError()))
        XCTAssertTrue(AccountHTTPClient.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(AccountHTTPClient.isCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertFalse(AccountHTTPClient.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(AccountHTTPClient.isCancellation(URLError(.notConnectedToInternet)))
        XCTAssertFalse(AccountHTTPClient.isCancellation(AccountHTTPError(status: 401, message: "Session expired")))
    }

}
