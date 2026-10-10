import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared bounded mesh. Linear color interpolation avoids cubic overshoot outside tested colors.
public struct AmbientGlowBackground: View {
    @Environment(\.appTheme) private var theme
    public let roomId: String?
    public init(roomId: String? = nil) { self.roomId = roomId }

    public var body: some View {
        let style = ThemeManager.shared.style(for: roomId)
        ZStack {
            theme.backgroundBase
            if theme.preset != .onyx {
                MeshGradient(width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5, 0.5], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: [
                        theme.backgroundBase, theme.meshColors[0], theme.backgroundBase,
                        theme.meshColors[1], theme.backgroundBase, theme.meshColors[2],
                        theme.backgroundBase, theme.meshColors[0], theme.backgroundBase
                    ], smoothsColors: false)
            }
            // Preserve room wallpaper selection, with a scheme-aware scrim for arbitrary photo colors.
            #if canImport(UIKit)
            if let image = style.customWallpaperImage {
                Image(uiImage: image).resizable().scaledToFill()
                theme.wallpaperScrim
            } else if let url = style.customWallpaperURL {
                wallpaper(url)
            }
            #else
            if let url = style.customWallpaperURL { wallpaper(url) }
            #endif
        }
        .ignoresSafeArea()
    }

    private func wallpaper(_ url: URL) -> some View {
        AuthorizedWallpaper(url: url).overlay(theme.wallpaperScrim)
    }
}

@MainActor
private struct AuthorizedWallpaper: View {
    let url: URL
    @State private var file: URL?
    var body: some View {
        Group {
            #if canImport(UIKit)
            if let file, let image = UIImage(contentsOfFile: file.path) { Image(uiImage: image).resizable().scaledToFill() }
            #else
            EmptyView()
            #endif
        }
        .task(id: url) { file = try? await AuthSessionManager.shared.mediaFile(url) }
    }
}
