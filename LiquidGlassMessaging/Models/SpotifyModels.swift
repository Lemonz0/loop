import Foundation

struct SpotifyTrack: Codable, Sendable {
    let name: String
    let artists: String
    let album: String
    let artworkURL: URL?
    let trackURL: URL
    let durationMs: Int
    let progressMs: Int
    let observedAt: Date
    let expiresAt: Date
    func isFresh(at date: Date) -> Bool { expiresAt > date }
    func progress(at date: Date) -> Double {
        guard durationMs > 0 else { return 0 }
        return min(1, max(0, (Double(progressMs) + max(0, date.timeIntervalSince(observedAt)) * 1000) / Double(durationMs)))
    }
}
struct SpotifyPresence: Codable, Sendable {
    let connected: Bool
    let displayName: String?
    let profileURL: URL?
    let track: SpotifyTrack?
}
struct SpotifySettings: Decodable, Sendable {
    let available: Bool
    let connected: Bool
    let sharing: Bool
    let reconnect: Bool
    let displayName: String?
    let profileURL: URL?
}
struct SpotifyAuthorization: Decodable, Sendable {
    let authorizationURL: URL
    let attempt: String
}
