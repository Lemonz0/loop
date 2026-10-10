import SwiftUI

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var spotifyConnection = SpotifyConnectionManager.shared
    @State private var settings = ProfileSettings()
    @State private var links = ""
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()
                ScrollView {
                    GlassEffectContainer(spacing: 14) {
                        VStack(spacing: 14) {
                            ProfileCard()
                            SpotifySettingsView()
                            VStack(alignment: .leading, spacing: 14) {
                                Text("About you").font(.headline)
                                TextField("Bio", text: $settings.bio, axis: .vertical).lineLimit(3...8)
                                TextField("Pronouns (optional)", text: $settings.pronouns)
                                TextField("Custom status", text: $settings.status)
                                TextField("HTTPS links, one per line", text: $links, axis: .vertical).lineLimit(2...5).textInputAutocapitalization(.never).autocorrectionDisabled()
                            }.padding(20).circleSurface()
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Privacy").font(.headline)
                                Toggle("Private profile", isOn: $settings.private)
                                Toggle("Share presence", isOn: Binding(get: { settings.presence == "everyone" }, set: { settings.presence = $0 ? "everyone" : "nobody" }))
                                Toggle("Share my local time", isOn: $settings.showLocalTime)
                                Text("Private profiles require you to add a person as a contact before they can message or call you.").font(.footnote).foregroundStyle(theme.secondaryText)
                            }.padding(20).circleSurface()
                            if !loaded { Text("Loading settings").redacted(reason: .placeholder) }
                            if let error { Text(error).foregroundStyle(theme.destructive); if !loaded { Button("Retry") { Task { await load() } }.buttonStyle(.glass) } }
                        }.padding(20)
                    }
                }
            }.navigationTitle("Edit profile")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(saving || spotifyConnection.isConnecting) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!loaded || saving || spotifyConnection.isConnecting || settings.bio.count > 2000 || settings.pronouns.count > 80 || settings.status.count > 140) }
                }.interactiveDismissDisabled(saving || spotifyConnection.isConnecting).task { await load() }
        }
    }
    private func load() async {
        do { settings = try await ProfileRepository.shared.request("api/profiles/settings"); links = settings.links.joined(separator: "\n"); loaded = true; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func save() {
        guard !saving else { return }; saving = true
        settings.timeZone = TimeZone.current.identifier
        settings.links = links.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        Task { defer { saving = false }; do {
            let _: PersonCard = try await ProfileRepository.shared.request("api/profiles/settings", body: JSONEncoder().encode(settings))
            ProfileRepository.shared.reset(); HapticFeedback.success(); dismiss()
        } catch { self.error = error.localizedDescription } }
    }
}
#Preview("Edit account · dark") { ProfileEditorView().circlePreviewTheme(.aurora) }
#Preview("Edit account · light") { ProfileEditorView().circlePreviewTheme(.daylight) }
