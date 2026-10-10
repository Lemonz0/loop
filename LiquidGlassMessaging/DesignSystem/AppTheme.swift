import SwiftUI

public struct AppTheme: Equatable, Sendable {
    public let preset: ThemePreset
    public init(preset: ThemePreset) { self.preset = preset }
    public var palette: ThemePalette { preset.palette }
    public var colorScheme: ColorScheme { palette.isLight ? .light : .dark }
    public var secondaryText: Color { palette.isLight ? .primary : .secondary }
    public var backgroundBase: Color { Color(themeHex: palette.base) }
    public var meshColors: [Color] { palette.mesh.map { Color(themeHex: $0) } }
    public var accent: Color { Color(themeHex: palette.accent) }
    public var success: Color { Color(themeHex: palette.success) }
    public var destructive: Color { Color(themeHex: palette.destructive) }
    public var warning: Color { Color(themeHex: palette.warning) }
    // Tint text-heavy surfaces only subtly; full accent is reserved for native button styles.
    public var glassTint: Color { accent.opacity(0.08) }
    public var storyRingColors: [Color] {
        palette.storyRingColors.map { Color(themeHex: $0) }
    }
    public var storyScrimColors: [Color] { [Color(themeHex: palette.mediaScrim).opacity(0.8), Color(themeHex: palette.mediaScrim).opacity(0)] }
    public var wallpaperScrim: Color { backgroundBase.opacity(0.96) }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme(preset: .onyx)
}
public extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
private extension Color {
    init(themeHex: UInt32) {
        self.init(.sRGB, red: Double((themeHex >> 16) & 255) / 255,
                  green: Double((themeHex >> 8) & 255) / 255,
                  blue: Double(themeHex & 255) / 255, opacity: 1)
    }
}
