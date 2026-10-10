import SwiftUI

/// Native selection rows and checkmarks; selection never paints a custom filled card.
@MainActor
public struct AppearanceSettingsView: View {
    @Environment(\.appTheme) private var theme
    @State private var themeManager = ThemeManager.shared
    public init() {}

    public var body: some View {
        ZStack {
            AmbientGlowBackground()
            ScrollView {
                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        ForEach(ThemePreset.allCases) { preset in
                            Button {
                                HapticFeedback.selection()
                                themeManager.activePreset = preset
                            } label: {
                                HStack(spacing: 14) {
                                    ThemePreviewSwatch(preset: preset)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.rawValue)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(preset.description)
                                            .font(.subheadline)
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                    Spacer(minLength: 0)
                                    if themeManager.activePreset == preset {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(theme.accent)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: 22))
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22))
                            .accessibilityValue(themeManager.activePreset == preset ? "Selected" : "")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 96)
            }
        }
        .navigationTitle("Appearance & Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemePreviewSwatch: View {
    let preset: ThemePreset
    private var previewTheme: AppTheme { AppTheme(preset: preset) }
    var body: some View {
        ZStack {
            // Swatches are miniature backgrounds, not contrast patches behind UI content.
            LinearGradient(colors: [previewTheme.backgroundBase] + previewTheme.meshColors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: preset == .onyx ? "moon.fill" : "sparkles")
                .foregroundStyle(previewTheme.accent)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, previewTheme.colorScheme)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { AppearanceSettingsView() }
}
