import Foundation

/// Persisted Onyx value is intentionally unchanged. Accept both historic labels and wire names.
public enum ThemePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case onyx = "Onyx (Pure OLED Black)"
    case aurora = "Aurora (Deep Color)"
    case daylight = "Daylight (Light Glass)"

    public var id: String { rawValue }
    public var shortName: String {
        switch self {
        case .onyx: return "Onyx"
        case .aurora: return "Aurora"
        case .daylight: return "Daylight"
        }
    }
    public var description: String {
        switch self {
        case .onyx: return "True #000000 OLED black with native glass highlights."
        case .aurora: return "Deep indigo, violet, teal, and blue beneath dark glass."
        case .daylight: return "Soft off-white and pastel color beneath light glass."
        }
    }
    public static func restored(from value: String?) -> Self {
        guard let value else { return .onyx }
        if let exact = Self(rawValue: value) { return exact }
        switch value.lowercased() {
        case "slate", "slate (neutral grey)", "aurora": return .aurora
        case "frost", "frost (light glass)", "daylight": return .daylight
        default: return .onyx
        }
    }
    public var palette: ThemePalette {
        switch self {
        case .onyx:
            return ThemePalette(isLight: false, base: 0x000000,
                mesh: [0x000000, 0x000000, 0x000000],
                accent: 0x70B8FF, success: 0x58DCA0, destructive: 0xFF8A96, warning: 0xF2CC70)
        case .aurora:
            return ThemePalette(isLight: false, base: 0x080E24,
                mesh: [0x24203F, 0x103238, 0x152D50],
                accent: 0x70B8FF, success: 0x58DCA0, destructive: 0xFF8A96, warning: 0xF2CC70)
        case .daylight:
            return ThemePalette(isLight: true, base: 0xFAF9F6,
                mesh: [0xDFECFA, 0xEBE3F6, 0xFAE5D9],
                accent: 0x174E9C, success: 0x12643F, destructive: 0xA11D36, warning: 0x795000)
        }
    }
}

/// All literal theme colors live here. UI text uses SwiftUI's semantic foreground styles.
public struct ThemePalette: Sendable, Equatable {
    public let isLight: Bool
    public let base: UInt32
    public let mesh: [UInt32]
    public let accent: UInt32
    public let success: UInt32
    public let destructive: UInt32
    public let warning: UInt32
    public var storyRingColors: [UInt32] {
        isLight ? [0xA75A12, 0xA11D58, 0x7041A0, accent] : [0xE88630, 0xE64E85, 0xA673D9, accent]
    }
    public var mediaScrim: UInt32 { 0x000000 }
    public var backgrounds: [UInt32] { [base] + mesh }
    public var statusTokens: [(String, UInt32)] {
        [("accent", accent), ("success", success), ("destructive", destructive), ("warning", warning)]
    }
    public static func luminance(_ hex: UInt32) -> Double {
        func linear(_ component: UInt32) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((hex >> 16) & 255)
            + 0.7152 * linear((hex >> 8) & 255) + 0.0722 * linear(hex & 255)
    }
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
