import SwiftUI

/// Focused sub-page for Notifications & Audio/Haptic preferences using native Liquid Glass cards.
@MainActor
public struct NotificationsSettingsView: View {
    @Environment(\.appTheme) private var theme
    @AppStorage("settings_push_enabled") private var pushNotificationsEnabled: Bool = true
    @AppStorage("settings_in_app_sounds") private var inAppSoundsEnabled: Bool = true
    @AppStorage("settings_haptics_level") private var hapticLevel: String = "Spring Rigid"

    public init() {}

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Alerts Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ALERTS")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.leading, 6)

                        GlassEffectContainer(spacing: 14) {
                            VStack(spacing: 14) {
                                // Push Notifications Card
                                Toggle(isOn: $pushNotificationsEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Push Notifications")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                        Text("Instant alerts for new incoming circle messages.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                }
                                .tint(theme.accent)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                                // In-App Audio Chimes Card
                                Toggle(isOn: $inAppSoundsEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("In-App Audio Chimes")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                        Text("Audible confirmation when messages arrive.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                }
                                .tint(theme.accent)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                        }
                    }

                    // Haptics Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HAPTICS")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.leading, 6)

                        GlassEffectContainer(spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Haptic Feedback")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text("Tactile response for typing and interactions.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.secondaryText)
                                }

                                Spacer()

                                Picker("Haptic Feedback", selection: $hapticLevel) {
                                    Text("Off").tag("Off")
                                    Text("Subtle").tag("Subtle")
                                    Text("Spring Rigid").tag("Spring Rigid")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .tint(theme.accent)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }

                    // Footer explanatory card
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.secondaryText)
                        Text("Notifications and alerts are delivered with hardware end-to-end encryption preservation.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 96)
            }
            .scrollEdgeEffectStyle()
        }
        .navigationTitle("Notifications & Sounds")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotificationsSettingsView()
    }

}
