import SwiftUI

struct SpotifySettingsView: View {
    @Environment(\.appTheme) private var theme
    @State private var settings: SpotifySettings?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmsDisconnect = false
    @State private var connection = SpotifyConnectionManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpotifyLogo()
            if let settings {
                if settings.connected {
                    if let url = settings.profileURL { Link(settings.displayName ?? "Spotify profile", destination: url).font(.headline).frame(minHeight: 44) }
                    Toggle("Share listening with mutual contacts", isOn: Binding(get: { settings.sharing }, set: { changeSharing($0) })).disabled(busy || connection.isConnecting)
                    Text("Only people you’ve both added can see your music. Paused playback and Spotify private sessions are hidden.").font(.footnote).foregroundStyle(theme.secondaryText)
                    if settings.reconnect { Text("Spotify needs you to reconnect your account.").font(.footnote).foregroundStyle(theme.secondaryText); connectButton("Reconnect Spotify") }
                    Button("Disconnect Spotify", role: .destructive) { confirmsDisconnect = true }.buttonStyle(.glass).frame(minHeight: 44).disabled(busy || connection.isConnecting)
                } else if settings.available {
                    Text("Connect your account to show your Spotify profile. Listening activity stays private until you enable sharing.").font(.footnote).foregroundStyle(theme.secondaryText)
                    connectButton("Connect Spotify")
                } else { Text("Spotify hasn’t been configured on this server yet.").font(.footnote).foregroundStyle(theme.secondaryText) }
            } else { Text("Loading Spotify connection").redacted(reason: .placeholder) }
            if let error { Text(error).font(.footnote).foregroundStyle(theme.destructive); Button("Retry") { Task { await load() } }.buttonStyle(.glass).disabled(busy || connection.isConnecting) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).circleSurface()
            .task { await load() }
            .confirmationDialog("Disconnect Spotify and remove your listening activity?", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { disconnect() }; Button("Cancel", role: .cancel) {}
            }
    }
    private func connectButton(_ title: String) -> some View {
        Button(connection.isConnecting ? "Connecting Spotify…" : title) {
            Task { do { try await connection.connect(); await load(); HapticFeedback.success() } catch { if !AccountHTTPClient.isCancellation(error) { self.error = error.localizedDescription } } }
        }.buttonStyle(.glassProminent).frame(minHeight: 44).disabled(busy || connection.isConnecting)
    }
    private func load() async {
        do { settings = try await ProfileRepository.shared.request("api/spotify/settings"); error = nil }
        catch { if !AccountHTTPClient.isCancellation(error) { self.error = error.localizedDescription } }
    }
    private func changeSharing(_ enabled: Bool) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do {
            struct Body: Encodable { let enabled: Bool }
            settings = try await ProfileRepository.shared.request("api/spotify/sharing", body: JSONEncoder().encode(Body(enabled: enabled)))
            ProfileRepository.shared.reset(); HapticFeedback.success(); error = nil
        } catch { self.error = error.localizedDescription } }
    }
    private func disconnect() {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do { settings = try await ProfileRepository.shared.request("api/spotify/disconnect", body: Data("{}".utf8)); ProfileRepository.shared.reset(); error = nil } catch { self.error = error.localizedDescription } }
    }
}
#Preview("Spotify settings · dark") { SpotifySettingsView().padding().circlePreviewTheme(.aurora) }
#Preview("Spotify settings · light") { SpotifySettingsView().padding().circlePreviewTheme(.daylight) }
