import SwiftUI
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

/// Dynamic styling parameters derived from the active preset or custom room wallpaper.
public struct ThemeStyle: Sendable, Equatable {
    public let preset: ThemePreset
    public let customWallpaperURL: URL?
    #if canImport(UIKit)
    public let customWallpaperImage: UIImage?
    #endif
    public let isLightMode: Bool

    #if canImport(UIKit)
    public init(
        preset: ThemePreset,
        customWallpaperURL: URL? = nil,
        customWallpaperImage: UIImage? = nil,
        isLightMode: Bool
    ) {
        self.preset = preset
        self.customWallpaperURL = customWallpaperURL
        self.customWallpaperImage = customWallpaperImage
        self.isLightMode = isLightMode
    }
    #else
    public init(
        preset: ThemePreset,
        customWallpaperURL: URL? = nil,
        isLightMode: Bool
    ) {
        self.preset = preset
        self.customWallpaperURL = customWallpaperURL
        self.isLightMode = isLightMode
    }
    #endif

    public var backgroundColor: Color { AppTheme(preset: preset).backgroundBase }
    public var textPrimary: Color { .primary }
    public var textSecondary: Color { .secondary }

}

/// Central observable theme engine managing local presets and server-synchronized room wallpapers.
@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    // Global user preference
    public var activePreset: ThemePreset {
        didSet {
            UserDefaults.standard.set(activePreset.rawValue, forKey: "liquidglass_active_preset")
            AppLogger.shared.info(.theme, "User changed global theme preset to: \(activePreset.shortName)")
        }
    }

    // Synchronized room themes: roomId -> RoomTheme
    public private(set) var roomThemes: [String: RoomTheme] = [:]

    #if canImport(UIKit)
    // Local memory cache for custom room wallpapers
    public private(set) var customWallpaperImages: [String: UIImage] = [:]
    #endif

    private init() {
        activePreset = ThemePreset.restored(from: UserDefaults.standard.string(forKey: "liquidglass_active_preset"))
        UserDefaults.standard.set(activePreset.rawValue, forKey: "liquidglass_active_preset")
    }

    // MARK: - Active Style Resolver

    public func style(for roomId: String? = nil) -> ThemeStyle {
        guard let roomId = roomId, let roomTheme = roomThemes[roomId] else {
            #if canImport(UIKit)
            return ThemeStyle(
                preset: activePreset,
                customWallpaperURL: nil,
                customWallpaperImage: nil,
                isLightMode: activePreset == .daylight
            )
            #else
            return ThemeStyle(
                preset: activePreset,
                customWallpaperURL: nil,
                isLightMode: activePreset == .daylight
            )
            #endif
        }

        if roomTheme.themeType == "custom", let urlStr = roomTheme.wallpaperUrl, let url = URL(string: urlStr) {
            #if canImport(UIKit)
            let localImage = customWallpaperImages[roomId]
            return ThemeStyle(
                preset: activePreset,
                customWallpaperURL: url,
                customWallpaperImage: localImage,
                isLightMode: activePreset == .daylight
            )
            #else
            return ThemeStyle(
                preset: activePreset,
                customWallpaperURL: url,
                isLightMode: activePreset == .daylight
            )
            #endif
        }

        if let presetStr = roomTheme.presetName, !presetStr.isEmpty {
            let matching = ThemePreset.restored(from: presetStr)
            #if canImport(UIKit)
            return ThemeStyle(
                preset: matching,
                customWallpaperURL: nil,
                customWallpaperImage: nil,
                isLightMode: matching == .daylight
            )
            #else
            return ThemeStyle(
                preset: matching,
                customWallpaperURL: nil,
                isLightMode: matching == .daylight
            )
            #endif
        }

        #if canImport(UIKit)
        return ThemeStyle(
            preset: activePreset,
            customWallpaperURL: nil,
            customWallpaperImage: nil,
            isLightMode: activePreset == .daylight
        )
        #else
        return ThemeStyle(
            preset: activePreset,
            customWallpaperURL: nil,
            isLightMode: activePreset == .daylight
        )
        #endif
    }

    // MARK: - Incoming WebSocket Synchronization

    public func handleIncomingRoomTheme(_ theme: RoomTheme) {
        roomThemes[theme.roomId] = theme
        AppLogger.shared.info(.theme, "Applied synchronized theme for room: \(theme.roomId)", metadata: [
            "themeType": theme.themeType,
            "wallpaper": theme.wallpaperUrl ?? "none",
            "updatedBy": theme.updatedBy ?? "circle"
        ])
    }

    // MARK: - Wallpaper Upload & Broadcast

    #if canImport(UIKit)
    public func setCustomWallpaper(
        for roomId: String,
        image: UIImage,
        chatStore: ChatStore,
        uploader: MediaUploadManager
    ) async {
        customWallpaperImages[roomId] = image
        AppLogger.shared.info(.theme, "Encoding and uploading room wallpaper for \(roomId)...")

        guard let data = image.jpegData(compressionQuality: 0.82) else {
            AppLogger.shared.error(.theme, "Failed to encode JPEG wallpaper")
            return
        }

        do {
            let remoteURL = try await uploader.uploadRawMedia(
                data: data,
                fileName: "wallpaper_\(roomId)_\(Int(Date().timeIntervalSince1970)).jpg",
                serverBaseURL: AppEnvironment.shared.serverBaseURL
            )

            let theme = RoomTheme(
                roomId: roomId,
                themeType: "custom",
                wallpaperUrl: remoteURL.absoluteString,
                updatedBy: AuthSessionManager.shared.currentSession?.user.displayName ?? "Friend",
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )

            roomThemes[roomId] = theme

            // Broadcast over WebSocket to group
            let envelope = ClientMessageEnvelope(
                type: .updateRoomTheme,
                roomId: roomId,
                roomTheme: theme
            )
            try await chatStore.webSocketActor.send(envelope: envelope)

            AppLogger.shared.info(.theme, "Broadcasted custom room wallpaper update to circle", metadata: [
                "roomId": roomId,
                "url": remoteURL.absoluteString
            ])
            HapticFeedback.success()
        } catch {
            AppLogger.shared.error(.theme, "Wallpaper upload failed: \(error.localizedDescription)")
            HapticFeedback.error()
        }
    }
    #endif

    public func resetRoomTheme(for roomId: String, chatStore: ChatStore) async {
        #if canImport(UIKit)
        customWallpaperImages.removeValue(forKey: roomId)
        #endif
        let theme = RoomTheme(
            roomId: roomId,
            themeType: "preset",
            presetName: activePreset.shortName.lowercased(),
            updatedBy: AuthSessionManager.shared.currentSession?.user.displayName ?? "Friend",
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        roomThemes[roomId] = theme

        let envelope = ClientMessageEnvelope(
            type: .updateRoomTheme,
            roomId: roomId,
            roomTheme: theme
        )
        try? await chatStore.webSocketActor.send(envelope: envelope)
        AppLogger.shared.info(.theme, "Reset room theme to default preset for: \(roomId)")
        HapticFeedback.rigid()
    }
}
