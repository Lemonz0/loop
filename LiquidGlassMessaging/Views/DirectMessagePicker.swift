import SwiftUI

struct DirectMessagePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    let users: [User]
    var onOpen: (User) async -> Bool
    @State private var opening: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()
                ScrollView {
                    GlassEffectContainer(spacing: 14) {
                        VStack(spacing: 14) {
                            if users.isEmpty { ContentUnavailableView("No friends yet", systemImage: "person.2", description: Text("Invite a friend to your circle first.")) }
                            ForEach(users) { user in
                                Button {
                                    opening = user.id; error = nil
                                    Task {
                                        if !(await onOpen(user)) { error = AuthSessionManager.shared.lastError ?? "Could not open this chat."; AuthSessionManager.shared.lastError = nil }
                                        opening = nil
                                    }
                                } label: {
                                    HStack(spacing: 12) { CircleAvatar(user: user); Text(user.name).font(.headline); Spacer(); if opening == user.id { ProgressView() } }
                                        .padding(14).frame(minHeight: 44)
                                }.buttonStyle(.plain).circleSurface(interactive: true).disabled(opening != nil)
                                    .accessibilityLabel("Message \(user.name)")
                            }
                            if let error { Text(error).font(.footnote).foregroundStyle(theme.destructive) }
                        }.padding(20)
                    }
                }
            }.navigationTitle("Direct message")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(opening != nil) } }
                .interactiveDismissDisabled(opening != nil)
        }
    }
}
#Preview("DM picker · dark") { DirectMessagePicker(users: MockData.snapshot().friends, onOpen: { _ in true }).circlePreviewTheme(.aurora) }
#Preview("DM picker · light") { DirectMessagePicker(users: MockData.snapshot().friends, onOpen: { _ in true }).circlePreviewTheme(.daylight) }
