# Theme contrast

Production colors are centralized in ThemePalette.swift. Run `node scripts/check-theme-contrast.cjs --write-doc` to regenerate this table from those definitions.

WCAG ratios use sRGB linearization and (Llighter + 0.05) / (Ldarker + 0.05). Every base, every mesh vertex, the conservative RGB component envelope, and the worst arbitrary wallpaper after the 96% scheme-aware scrim are checked. Smooth color interpolation is disabled to prevent cubic overshoot. Status and accent tokens pass 4.5:1 because they also appear in small text; this exceeds the 3:1 UI requirement.

| Theme | Token pair (minimum over tested backgrounds) | Ratio | Threshold | Result |
|---|---|---:|---:|---|
| Onyx | primary / backdrop | 19.80:1 | 4.5:1 | PASS |
| Onyx | supporting / backdrop | 6.32:1 | 4.5:1 | PASS |
| Onyx | accent / backdrop | 9.42:1 | 4.5:1 | PASS |
| Onyx | success / backdrop | 11.46:1 | 4.5:1 | PASS |
| Onyx | destructive / backdrop | 8.79:1 | 4.5:1 | PASS |
| Onyx | warning / backdrop | 12.87:1 | 4.5:1 | PASS |
| Aurora | primary / backdrop | 12.75:1 | 4.5:1 | PASS |
| Aurora | supporting / backdrop | 4.94:1 | 4.5:1 | PASS |
| Aurora | accent / backdrop | 6.06:1 | 4.5:1 | PASS |
| Aurora | success / backdrop | 7.38:1 | 4.5:1 | PASS |
| Aurora | destructive / backdrop | 5.66:1 | 4.5:1 | PASS |
| Aurora | warning / backdrop | 8.29:1 | 4.5:1 | PASS |
| Daylight | primary / backdrop | 16.13:1 | 4.5:1 | PASS |
| Daylight | supporting / backdrop | 16.13:1 | 4.5:1 | PASS |
| Daylight | accent / backdrop | 6.19:1 | 4.5:1 | PASS |
| Daylight | success / backdrop | 5.52:1 | 4.5:1 | PASS |
| Daylight | destructive / backdrop | 5.88:1 | 4.5:1 | PASS |
| Daylight | warning / backdrop | 5.45:1 | 4.5:1 | PASS |

Supporting text uses semantic primary in Daylight and semantic secondary in dark themes. Standard light secondary text was only about 3.15:1 over these backgrounds, so it is deliberately not used. The smallest passing ratio is Aurora supporting text; keep mesh luminance restrained.

The portable checker uses reference label components (dark primary FFFFFF, dark secondary EBEBF5 at 60%, light primary 000000). These are verification inputs, never hard-coded UI text. The hostless ThemeContrastTests target resolves actual UIKit label/secondaryLabel colors on the selected iOS 26 simulator and checks the same backgrounds, plus migration and Onyx invariants. CI runs both the portable check and XCTest, then archives the app.

These numbers certify the palette/backdrop contract, not rendered pixels: SwiftUI semantic styles, vibrant text, native regular glass, tint adaptation, native prominent button labels, accessibility settings, arbitrary media and system dialogs are composited by Apple. Screens were audited in code; visual verification of every screen on an iOS 26 device/simulator is still required. Do not claim these arithmetic tests certify all rendered glass surfaces.

Reviewed screens: Settings root/profile and all five sub-pages; Home; Messages/search/contacts/chat cards; alternate room list and floating tab bar; chat header/composer/bubbles/typing indicator; authentication; call tiles/controls; live console; Add Contact/New Group/Archived sheets; full-screen media and cache confirmation dialog.

No Materials, blur effects, artificial glass strokes/shadows, or opaque UI contrast patches are used. Solid base colors and swatch gradients are background/preview content. Status dots are meaningful colored indicators. Text-heavy surfaces use native regular glass; prominent buttons keep system-controlled label styling.

Apple API references: [MeshGradient initializer](https://developer.apple.com/documentation/swiftui/meshgradient/init(width:height:points:colors:background:smoothscolors:colorspace:)), [preferredColorScheme](https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:)), [tint](https://developer.apple.com/documentation/swiftui/view/tint(_:)), [Glass](https://developer.apple.com/documentation/swiftui/glass), [SwiftUI and Liquid Glass WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/). MeshGradient requires iOS 18; Liquid Glass requires iOS 26, matching project.yml.
