import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public extension View {
    func circleSurface(radius: CGFloat = 28, interactive: Bool = false) -> some View {
        modifier(CircleSurfaceModifier(radius: radius, interactive: interactive))
    }
    func circlePreviewTheme(_ preset: ThemePreset) -> some View {
        let theme = AppTheme(preset: preset)
        return environment(\.appTheme, theme).environment(\.colorScheme, theme.colorScheme)
            .preferredColorScheme(theme.colorScheme).tint(theme.accent)
    }
}

private struct CircleSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.appTheme) private var theme
    let radius: CGFloat
    let interactive: Bool
    func body(content: Content) -> some View {
        let glass = (reduceTransparency || contrast == .increased) ? Glass.regular.tint(theme.backgroundBase) : Glass.regular
        content.glassEffect(interactive ? glass.interactive() : glass,
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct CircleAvatar: View {
    @Environment(\.appTheme) private var theme
    let user: User
    var size: CGFloat = 40
    var opensProfile = true
    var generic = false
    var body: some View {
        ZStack {
            if generic {
                Image(systemName: "person.fill").font(.system(size: size * 0.4)).foregroundStyle(theme.secondaryText)
            } else if let url = user.avatarURL {
                CircleMediaView(media: CircleMedia(url: url), placeholderSymbol: "person.fill", cachesAvatar: true)
            } else {
                Text(user.name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased())
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .glassEffect(.regular.tint(theme.glassTint), in: Circle())
        .frame(minWidth: opensProfile ? 44 : size, minHeight: opensProfile ? 44 : size)
        .profileEntry(user.id, name: user.name, enabled: opensProfile)
        .accessibilityHidden(!opensProfile)
    }
}

struct CircleMediaView: View {
    @Environment(\.appTheme) private var theme
    let media: CircleMedia
    var placeholderSymbol = "photo"
    var contentMode: ContentMode = .fill
    var cachesAvatar = false
    var cachesPost = false
    var body: some View {
        GeometryReader { geometry in
            Group {
                #if canImport(UIKit)
                if let data = media.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                } else {
                    remoteImage
                }
                #else
                remoteImage
                #endif
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
    private var remoteImage: some View {
        Group {
            if let url = media.url, url.host == nil || url.host == AuthSessionManager.shared.savedServerURL?.host {
                PrivateSocialImage(url: url, placeholderSymbol: placeholderSymbol, contentMode: contentMode, cache: cachesAvatar ? .avatars : cachesPost ? .posts : nil)
            } else {
                AsyncImage(url: media.url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure: placeholder.overlay { Image(systemName: placeholderSymbol).font(.title).foregroundStyle(.primary) }
                    default: placeholder.overlay { ProgressView().tint(theme.accent) }
                    }
                }
            }
        }
    }
    private var placeholder: some View {
        LinearGradient(colors: theme.meshColors + [theme.backgroundBase], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct CircleIconButton: View {
    let symbol: String
    let label: String
    var compact = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: compact ? 28 : 44, height: compact ? 28 : 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(compact ? .small : .regular)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }
}

struct CircleErrorAlert: ViewModifier {
    @Bindable var model: CircleViewModel
    func body(content: Content) -> some View {
        content.alert("Loop", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

#Preview("Avatar · dark") { CircleAvatar(user: MockData.snapshot().friends[1], size: 62).circlePreviewTheme(.aurora) }
#Preview("Avatar · light") { CircleAvatar(user: MockData.snapshot().friends[1], size: 62).circlePreviewTheme(.daylight) }
#Preview("Media · dark") { CircleMediaView(media: MockData.snapshot().posts[0].media[0]).frame(height: 300).circlePreviewTheme(.aurora) }
#Preview("Media · light") { CircleMediaView(media: MockData.snapshot().posts[0].media[0]).frame(height: 300).circlePreviewTheme(.daylight) }
#Preview("Icon · dark") { CircleIconButton(symbol: "plus", label: "Create") {}.circlePreviewTheme(.aurora) }
#Preview("Icon · light") { CircleIconButton(symbol: "plus", label: "Create") {}.circlePreviewTheme(.daylight) }

@MainActor
private struct PrivateSocialImage: View {
    let url: URL
    var placeholderSymbol = "photo.badge.exclamationmark"
    var contentMode: ContentMode = .fill
    var cache: PrivateImageCache?
    @State private var loadedImage: UIImage?
    @State private var loadedURL: URL?
    @State private var file: URL?
    @State private var failed = false
    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = cache != nil ? cache?.cachedImage(for: url) ?? (loadedURL == url ? loadedImage : nil) : file.flatMap({ UIImage(contentsOfFile: $0.path) }) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            }
            else if failed { Image(systemName: placeholderSymbol).foregroundStyle(.primary) }
            else { ProgressView() }
            #else
            Image(systemName: "photo")
            #endif
        }
        .id(url)
        .task(id: url) {
            file = nil; loadedImage = nil; loadedURL = nil; failed = false
            do {
                if let cache {
                    let image = try await cache.image(for: url)
                    try Task.checkCancellation()
                    loadedImage = image; loadedURL = url
                } else {
                    let downloaded = try await AuthSessionManager.shared.mediaFile(url)
                    try Task.checkCancellation()
                    file = downloaded
                }
            }
            catch is CancellationError {} catch { failed = true }
        }
    }
}
