import SwiftUI

/// The profile and DM header use the same server-filtered, expiring playback payload.
struct SpotifyPresenceView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    let userID: String
    var compact = false
    var fallback = ""
    var showsOnlineDot = false
    private let preview: SpotifyPresence?
    @State private var presence: SpotifyPresence?
    @State private var store = AppEnvironment.shared.chatStore
    @State private var auth = AuthSessionManager.shared
    init(userID: String, compact: Bool = false, fallback: String = "", showsOnlineDot: Bool = false, preview: SpotifyPresence? = nil) {
        self.userID = userID; self.compact = compact; self.fallback = fallback; self.showsOnlineDot = showsOnlineDot; self.preview = preview
        _presence = State(initialValue: preview)
    }
    private var pollIdentity: SpotifyPollIdentity { SpotifyPollIdentity(userID: userID, revision: store.accountRevision, token: auth.currentSession?.token, active: scenePhase == .active) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { clock in
            let track = presence?.track.flatMap { $0.isFresh(at: clock.date) ? $0 : nil }
            if compact {
                if let track {
                    Link(destination: track.trackURL) {
                        HStack(spacing: 8) { SpotifyLogo(); Text(track.name + " — " + track.artists).lineLimit(1).truncationMode(.tail).foregroundStyle(theme.secondaryText) }
                    }.buttonStyle(.plain).accessibilityLabel("Listening on Spotify: \(track.name) by \(track.artists)")
                } else {
                    HStack(spacing: 5) { if showsOnlineDot { Circle().fill(theme.success).frame(width: 7, height: 7) }; Text(fallback).lineLimit(1).foregroundStyle(theme.secondaryText) }
                }
            } else if let presence, presence.connected, let profileURL = presence.profileURL {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { SpotifyLogo(); Spacer(); Text(track == nil ? "Spotify profile" : "Listening to").font(.caption.weight(.semibold)).foregroundStyle(theme.secondaryText) }
                    Link(destination: profileURL) { Label(presence.displayName ?? "Spotify profile", systemImage: "arrow.up.right").font(.subheadline.weight(.semibold)).lineLimit(1).frame(minHeight: 44) }
                    if let track {
                        HStack(alignment: .top, spacing: 14) {
                            if let artwork = track.artworkURL {
                                AsyncImage(url: artwork) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "music.note").foregroundStyle(theme.secondaryText) }
                                    .frame(width: 72, height: 72).accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(track.name).font(.headline).lineLimit(2)
                                Text(track.artists).font(.subheadline).foregroundStyle(theme.secondaryText).lineLimit(2)
                                Text(track.album).font(.caption).foregroundStyle(theme.secondaryText).lineLimit(1)
                            }
                        }
                        ProgressView(value: track.progress(at: clock.date)).tint(theme.accent).accessibilityLabel("Song progress")
                        Link("Open song in Spotify", destination: track.trackURL).font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).circleSurface()
            }
        }
        .task(id: pollIdentity) {
            if preview != nil { return }
            presence = nil
            guard pollIdentity.active, auth.isAuthenticated else { return }
            while !Task.isCancelled {
                do {
                    let value: SpotifyPresence = try await ProfileRepository.shared.request("api/spotify/users/\(userID)")
                    try Task.checkCancellation(); presence = value
                } catch { if !AccountHTTPClient.isCancellation(error) { presence = nil } }
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
            }
        }
        .onChange(of: store.accountRevision) { _, _ in if preview == nil { presence = nil } }
        .onChange(of: auth.currentSession?.token) { _, _ in if preview == nil { presence = nil } }
    }
}
private struct SpotifyPollIdentity: Hashable { let userID: String; let revision: Int; let token: String?; let active: Bool }
struct SpotifyLogo: View {
    var body: some View { Image("SpotifyLogo").resizable().scaledToFit().frame(width: 70, height: 22).accessibilityLabel("Spotify") }
}
private func spotifyPreview() -> SpotifyPresence {
    SpotifyPresence(connected: true, displayName: "Maya", profileURL: URL(string: "https://open.spotify.com/user/example"),
        track: SpotifyTrack(name: "A moment together", artists: "Preview artist", album: "Preview album", artworkURL: nil, trackURL: URL(string: "https://open.spotify.com/track/example")!, durationMs: 180000, progressMs: 48000, observedAt: .now, expiresAt: .now.addingTimeInterval(3600)))
}
#Preview("Spotify card · dark") { SpotifyPresenceView(userID: "preview", preview: spotifyPreview()).padding().circlePreviewTheme(.aurora) }
#Preview("Spotify card · light") { SpotifyPresenceView(userID: "preview", preview: spotifyPreview()).padding().circlePreviewTheme(.daylight) }
#Preview("Spotify DM · dark") { SpotifyPresenceView(userID: "preview", compact: true, preview: spotifyPreview()).font(.caption).padding().circlePreviewTheme(.aurora) }
#Preview("Spotify DM · light") { SpotifyPresenceView(userID: "preview", compact: true, preview: spotifyPreview()).font(.caption).padding().circlePreviewTheme(.daylight) }
