import XCTest
import Foundation

final class SpotifyCodecTests: XCTestCase {
    func testHiddenActivityDecodesWithoutTrackOrIdentity() throws {
        let value = try AccountCodec.decoder().decode(SpotifyPresence.self, from: Data(#"{"connected":false}"#.utf8))
        XCTAssertFalse(value.connected); XCTAssertNil(value.track); XCTAssertNil(value.profileURL)
    }
    func testPlaybackExpiryAndProgressUseServerDates() throws {
        let json = #"{"connected":true,"displayName":"Listener","profileURL":"https://open.spotify.com/user/listener","track":{"name":"Song","artists":"Artist","album":"Album","trackURL":"https://open.spotify.com/track/test","durationMs":180000,"progressMs":45000,"observedAt":"2026-10-10T12:00:00.000Z","expiresAt":"2026-10-10T12:00:35.000Z"}}"#
        let value = try AccountCodec.decoder().decode(SpotifyPresence.self, from: Data(json.utf8)), track = try XCTUnwrap(value.track)
        XCTAssertEqual(track.progress(at: track.observedAt), 0.25, accuracy: 0.001)
        XCTAssertEqual(track.progress(at: track.observedAt.addingTimeInterval(15)), 1.0 / 3.0, accuracy: 0.001)
        XCTAssertTrue(track.isFresh(at: track.observedAt.addingTimeInterval(34)))
        XCTAssertFalse(track.isFresh(at: track.observedAt.addingTimeInterval(35)))
        XCTAssertEqual(track.progress(at: track.observedAt.addingTimeInterval(1000)), 1)
    }
}
