import SwiftUI
import AVKit

#if canImport(UIKit)
import UIKit
#endif

/// Custom fluid media component featuring inline video playback with liquid-glass overlays
/// and an interactive drag-to-dismiss full-screen media sheet.
public struct InlineMediaView: View {
    @Environment(\.appTheme) private var theme
    public let attachment: MediaAttachment
    @State private var isFullScreenPresented: Bool = false

    public init(attachment: MediaAttachment) {
        self.attachment = attachment
    }

    public var body: some View {
        Group {
            switch attachment.mediaType {
            case .video:
                InlineVideoPlayerCard(attachment: attachment)
                    .onTapGesture {
                        isFullScreenPresented = true
                    }
            case .image:
                InlineImageCard(attachment: attachment)
                    .onTapGesture {
                        isFullScreenPresented = true
                    }
            case .audio:
                VoiceMessageView(attachment: attachment)
            case .document:
                InlineDocumentCard(attachment: attachment)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isFullScreenPresented) {
            FullScreenMediaSheet(attachment: attachment)
        }
        #else
        .sheet(isPresented: $isFullScreenPresented) {
            FullScreenMediaSheet(attachment: attachment)
        }
        #endif
    }
}

// MARK: - Inline Image Card

private struct InlineImageCard: View {
    @Environment(\.appTheme) private var theme
    let attachment: MediaAttachment

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LocalOrRemoteImage(localURL: attachment.localURL, remoteURL: attachment.remoteURL)
                .scaledToFill()

            // Size badge pill
            Text(attachment.formattedSize)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .liquidGlassPill(specularIntensity: 0.5, strokeWidth: 1.0)
                .padding(8)
        }
        .frame(maxWidth: 280, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.bubbleRadius, style: .continuous))
    }
}

// MARK: - Local or Remote Image Helper

@MainActor
private struct LocalOrRemoteImage: View {
    @Environment(\.appTheme) private var theme
    let localURL: URL?
    let remoteURL: URL?
    @State private var downloaded: URL?
    @State private var failed = false
    var body: some View {
        Group {
            #if canImport(UIKit)
            if let file = localURL ?? downloaded, let image = UIImage(contentsOfFile: file.path) {
                Image(uiImage: image).resizable()
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.primary)
            } else { ProgressView().tint(theme.accent) }
            #else
            Image(systemName: "photo")
            #endif
        }
        .task(id: remoteURL) {
            guard localURL == nil, let remoteURL else { return }
            do { downloaded = try await AuthSessionManager.shared.mediaFile(remoteURL) }
            catch { failed = true }
        }
    }
}

// MARK: - Inline Video Player Card

@MainActor
private struct InlineVideoPlayerCard: View {
    @Environment(\.appTheme) private var theme
    let attachment: MediaAttachment
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true) // Disable native controls in inline view
            } else {
                theme.backgroundBase.opacity(0.35)
            }

            // Liquid glass central playback trigger
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            // Bottom duration and size overlay
            VStack {
                Spacer()
                HStack {
                    if let duration = attachment.durationSeconds {
                        Label(formatDuration(duration), systemImage: "clock")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    Spacer()
                    Text(attachment.formattedSize)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)

                .padding(10)
            }
        }
        .frame(width: 270, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.bubbleRadius, style: .continuous))
        .task(id: attachment.remoteURL) {
            if let local = attachment.localURL { player = AVPlayer(url: local) }
            else if let remote = attachment.remoteURL {
                do { player = AVPlayer(url: try await AuthSessionManager.shared.mediaFile(remote)) }
                catch { }
            }
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        HapticFeedback.soft()
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Document Card

private struct InlineDocumentCard: View {
    @Environment(\.appTheme) private var theme
    let attachment: MediaAttachment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 24))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(attachment.formattedSize)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
        }
        .padding(12)
        .liquidGlass(cornerRadius: 16, specularIntensity: 0.3)
        .frame(maxWidth: 260)
    }
}

// MARK: - Full Screen Drag-To-Dismiss Media Sheet

@MainActor
public struct FullScreenMediaSheet: View {
    @Environment(\.appTheme) private var theme
    public let attachment: MediaAttachment
    @Environment(\.dismiss) private var dismiss

    @State private var dragOffset: CGSize = .zero
    @State private var player: AVPlayer?

    public init(attachment: MediaAttachment) {
        self.attachment = attachment
    }

    public var body: some View {
        ZStack {
            // Dark progressive backdrop responding to drag distance
            theme.backgroundBase
                .opacity(max(0.2, 1.0 - Double(abs(dragOffset.height) / 500)))
                .ignoresSafeArea()

            // Ambient soft glow
            AmbientGlowBackground()
                .opacity(0.4)

            // Content with interactive rubber-band scaling & translation
            Group {
                if attachment.mediaType == .video {
                    VideoPlayer(player: player)
                        .task {
                            if let local = attachment.localURL { player = AVPlayer(url: local) }
                            else if let remote = attachment.remoteURL, let file = try? await AuthSessionManager.shared.mediaFile(remote) { player = AVPlayer(url: file) }
                            player?.play()
                        }
                        .onDisappear { player?.pause() }
                } else {
                    LocalOrRemoteImage(localURL: attachment.localURL, remoteURL: attachment.remoteURL)
                        .scaledToFit()
                }
            }
            .offset(y: dragOffset.height)
            .scaleEffect(max(0.8, 1.0 - abs(dragOffset.height) / 1200))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 140 || abs(value.velocity.height) > 600 {
                            HapticFeedback.medium()
                            dismiss()
                        } else {
                            withAnimation(GlassTheme.sheetSpring) {
                                dragOffset = .zero
                            }
                        }
                    }
            )

            // Top floating dismiss pill
            VStack {
                HStack {
                    Spacer()
                    Button {
                        HapticFeedback.soft()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .padding()
                }
                Spacer()
            }
        }
    }
}
