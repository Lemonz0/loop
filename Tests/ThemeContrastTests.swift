import XCTest
import UIKit

/// Hostless simulator tests compile the production palette directly, without starting app services.
final class ThemeContrastTests: XCTestCase {
    func testPersistenceMigration() {
        XCTAssertEqual(ThemePreset.onyx.rawValue, "Onyx (Pure OLED Black)")
        for value in ["slate", "Slate (Neutral Grey)"] {
            XCTAssertEqual(ThemePreset.restored(from: value), .aurora)
        }
        for value in ["frost", "Frost (Light Glass)"] {
            XCTAssertEqual(ThemePreset.restored(from: value), .daylight)
        }
        for preset in ThemePreset.allCases {
            XCTAssertEqual(ThemePreset.restored(from: preset.rawValue), preset)
        }
        XCTAssertEqual(ThemePreset.restored(from: nil), .onyx)
        XCTAssertEqual(ThemePreset.restored(from: "unknown"), .onyx)
        XCTAssertEqual(ThemePreset.onyx.palette.base, 0)
        XCTAssertTrue(ThemePreset.onyx.palette.mesh.allSatisfy { $0 == 0 })
    }

    func testPaletteAndSemanticTextContrast() {
        for preset in ThemePreset.allCases {
            let palette = preset.palette
            let traits = UITraitCollection(userInterfaceStyle: palette.isLight ? .light : .dark)
            // Also check the RGB envelope, guarding interpolated mesh colors, and extreme photos
            // after the production 96% wallpaper scrim. Glass rendering remains system-owned.
            let channels: [UInt32] = [16, 8, 0]
            let envelope = channels.reduce(UInt32(0)) { result, shift in
                let values = palette.backgrounds.map { ($0 >> shift) & 255 }
                return result | ((palette.isLight ? values.min()! : values.max()!) << shift)
            }
            let photoExtreme: UInt32 = palette.isLight ? 0x000000 : 0xFFFFFF
            let photo = blend(palette.base, over: photoExtreme, alpha: 0.96)
            for background in palette.backgrounds + [envelope, photo] {
                for (name, color) in [
                    ("primary", UIColor.label),
                    ("supporting", palette.isLight ? UIColor.label : UIColor.secondaryLabel)
                ] {
                    let text = resolved(color, traits: traits, over: background)
                    XCTAssertGreaterThanOrEqual(ThemePalette.contrast(text, background), 4.5,
                        "\(preset.shortName) \(name) over \(String(background, radix: 16))")
                }
                for (name, color) in palette.statusTokens {
                    let ratio = ThemePalette.contrast(color, background)
                    XCTAssertGreaterThanOrEqual(ratio, 3, "\(preset.shortName) \(name) UI")
                    // Status colors are also used by small colored log and connection labels.
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(preset.shortName) \(name) text")
                }
            }
        }
    }

    func testStoryRingContrast() {
        for preset in ThemePreset.allCases {
            for color in preset.palette.storyRingColors {
                for background in preset.palette.backgrounds {
                    XCTAssertGreaterThanOrEqual(ThemePalette.contrast(color, background), 3,
                        "Story ring must remain distinct in \(preset.shortName)")
                }
            }
        }
    }

    private func resolved(_ color: UIColor, traits: UITraitCollection, over background: UInt32) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a))
        let channels: [(CGFloat, UInt32)] = [(r, 16), (g, 8), (b, 0)]
        return channels.reduce(UInt32(0)) { result, channel in
            let backdrop = CGFloat((background >> channel.1) & 255) / 255
            let value = UInt32(((channel.0 * a + backdrop * (1 - a)) * 255).rounded())
            return result | (value << channel.1)
        }
    }

    private func blend(_ foreground: UInt32, over background: UInt32, alpha: Double) -> UInt32 {
        [UInt32(16), 8, 0].reduce(UInt32(0)) { result, shift in
            let f = Double((foreground >> shift) & 255), b = Double((background >> shift) & 255)
            return result | (UInt32((f * alpha + b * (1 - alpha)).rounded()) << shift)
        }
    }
}
