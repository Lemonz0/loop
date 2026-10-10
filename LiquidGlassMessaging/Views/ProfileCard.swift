import SwiftUI
import PhotosUI
import ImageIO

#if canImport(UIKit)
import UIKit
#endif

/// Liquid Glass profile card displaying the authenticated user, live connection latency,
/// and interactive photo selector.
@MainActor
public struct ProfileCard: View {
    @Environment(\.appTheme) private var theme
    @State private var authManager = AuthSessionManager.shared
    @State private var chatStore = AppEnvironment.shared.chatStore
    @State private var logger = AppLogger.shared

    @State private var avatarLoading = false
    @State private var uploadPending = false
    @State private var displayName: String = ""
    @State private var selectedAvatarItem: PhotosPickerItem? = nil
    #if canImport(UIKit)
    @State private var avatarImage: UIImage? = nil
    #endif

    public init() {}

    public var body: some View {
        let avatarBadge = avatarWithBadgeView
        return VStack(spacing: 16) {
            HStack(spacing: 18) {
                // Avatar with Camera Change Badge
                #if os(iOS)
                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                    avatarBadge
                }.disabled(uploadPending || avatarLoading).accessibilityLabel("Change profile photo")
                .buttonStyle(.plain)
                .onChange(of: selectedAvatarItem) {
                    loadSelectedAvatar()
                }
                #else
                avatarWithBadgeView
                #endif

                // Name, User ID, and Connection Telemetry
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Display Name", text: $displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .onSubmit {
                            saveDisplayName()
                        }

                    Text("User ID: \(authManager.currentSession?.user.id ?? "guest_user")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)

                    // Live WebSocket Ping & Latency Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectionColor)
                            .frame(width: 7, height: 7)

                        Text(connectionLabel)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(connectionColor)

                        if case .connected = chatStore.connectionState {
                            Text("• \(chatStore.pingLatencyMs)ms")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .task(id: authManager.currentSession?.user.avatarURL) {
            #if canImport(UIKit)
            avatarImage = nil; avatarLoading = true
            defer { avatarLoading = false }
            if let remote = authManager.currentSession?.user.avatarURL,
               let file = try? await authManager.mediaFile(remote), authManager.currentSession?.user.avatarURL == remote { avatarImage = UIImage(contentsOfFile: file.path) }
            #endif
        }
        .alert("Profile", isPresented: Binding(get: { authManager.lastError != nil }, set: { if !$0 { authManager.lastError = nil } })) { Button("OK") { authManager.lastError = nil } } message: { Text(authManager.lastError ?? "") }
        .onAppear {
            self.displayName = authManager.currentSession?.user.displayName ?? "Friend"
        }
    }

    // MARK: - Avatar Subview

    private var avatarWithBadgeView: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main Avatar Circle
            #if canImport(UIKit)
            if let avatar = avatarImage {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(Circle())
            } else if avatarLoading {
                ProgressView().frame(width: 68, height: 68)
            } else {
                defaultAvatarView
            }
            #else
            defaultAvatarView
            #endif

            // Camera Edit Badge (Native Glass Circle)
            Image(systemName: "camera.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .glassEffect(.regular.interactive(), in: Circle())
                .offset(x: 4, y: 4)
        }
    }

    private var defaultAvatarView: some View {
        let initial = String(displayName.prefix(1)).uppercased()
        return Text(initial.isEmpty ? "A" : initial)
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: 68, height: 68)
            .glassEffect(.regular.tint(theme.glassTint), in: Circle())
    }

    // MARK: - Telemetry Helpers

    private var connectionColor: Color {
        switch chatStore.connectionState {
        case .connected: return theme.success
        case .connecting, .reconnecting: return theme.warning
        case .disconnected: return theme.destructive
        }
    }

    private var connectionLabel: String {
        switch chatStore.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Disconnected"
        }
    }

    // MARK: - Actions

    private func saveDisplayName() {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        authManager.updateProfile(displayName: trimmed)
        HapticFeedback.success()
        logger.info(.general, "User updated display name to: \(trimmed)")
    }

    private func loadSelectedAvatar() {
        guard let item = selectedAvatarItem else { return }
        uploadPending = true
        Task {
            defer { uploadPending = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary),
                      let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.9),
                      let url = authManager.savedServerURL else { throw CircleRepositoryError.emptyMedia }
                let remote = try await MediaUploadManager.shared.uploadRawMedia(data: jpeg, fileName: "avatar_\(UUID().uuidString).jpg", serverBaseURL: url)
                authManager.updateProfile(displayName: displayName, avatarURL: remote)
            } catch { authManager.lastError = error.localizedDescription }
            selectedAvatarItem = nil
        }
    }

}

// MARK: - Preview

#Preview("Profile card · dark") {
    ZStack {
        AmbientGlowBackground()
        ProfileCard()
            .padding()
    }.circlePreviewTheme(.aurora)
}

#Preview("Profile card · light") { ProfileCard().padding().circlePreviewTheme(.daylight) }
