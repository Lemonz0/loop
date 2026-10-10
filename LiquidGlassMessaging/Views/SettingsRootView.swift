import SwiftUI

/// Redesigned root settings menu split into focused categories,
/// featuring native Apple Liquid Glass navigation and live user telemetry.
@MainActor
public struct SettingsRootView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var authManager = AuthSessionManager.shared
    @State private var chatStore = AppEnvironment.shared.chatStore

    private let socialModel: CircleViewModel?
    public var isModal: Bool

    public init(isModal: Bool = false, socialModel: CircleViewModel? = nil) {
        self.socialModel = socialModel
        self.isModal = isModal
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                settingsBackground

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        if let socialModel {
                            TrollConsentCard(model: socialModel)
                        }

                        // Preferences & Tools Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PREFERENCES & TOOLS")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.secondaryText)
                                .padding(.leading, 6)

                            // Real Liquid Glass Container grouping spaced cards
                            GlassEffectContainer(spacing: 14) {
                                VStack(spacing: 14) {
                                    NavigationLink {
                                        AppearanceSettingsView()
                                    } label: {
                                        categoryCardContent(
                                            title: "Appearance & Theme",
                                            subtitle: "Presets, dark mode, and specular reflections",
                                            icon: "paintpalette.fill",
                                            iconColor: theme.accent
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                                    NavigationLink {
                                        NotificationsSettingsView()
                                    } label: {
                                        categoryCardContent(
                                            title: "Notifications & Sounds",
                                            subtitle: "Push alerts, audio chimes, and tactile haptics",
                                            icon: "bell.badge.fill",
                                            iconColor: theme.warning
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                                    NavigationLink {
                                        MediaStorageSettingsView()
                                    } label: {
                                        categoryCardContent(
                                            title: "Media & Storage",
                                            subtitle: "Storage limits, cache size, and cleanup",
                                            icon: "internaldrive.fill",
                                            iconColor: theme.accent
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                                    NavigationLink {
                                        ConnectionSettingsView()
                                    } label: {
                                        categoryCardContent(
                                            title: "Connection",
                                            subtitle: "Hub relay address and latency",
                                            icon: "network",
                                            iconColor: theme.accent
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                                    NavigationLink {
                                        DeveloperSettingsView()
                                    } label: {
                                        categoryCardContent(
                                            title: "Developer & Diagnostics",
                                            subtitle: "Real-time console and telemetry export",
                                            icon: "wrench.and.screwdriver.fill",
                                            iconColor: theme.accent
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                }
                            }
                        }

                        // Sign Out Section (Standalone Liquid Glass Card)
                        Button(role: .destructive) {
                            HapticFeedback.rigid()
                            chatStore.stop()
                            authManager.signOut()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Spacer()
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Sign Out of Loop")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                Spacer()
                            }
                            .foregroundStyle(theme.destructive)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive().tint(theme.destructive.opacity(0.12)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 110)
                }
                .scrollEdgeEffectStyle()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    // MARK: - Category Card Content Layout

    private func categoryCardContent(title: String, subtitle: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 42, height: 42)
                .glassEffect(.regular.tint(iconColor.opacity(0.35)), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Background

    private var settingsBackground: some View {
        AmbientGlowBackground()
    }
}

// MARK: - Preview

#Preview("Settings · dark") { SettingsRootView(socialModel: CircleViewModel()).circlePreviewTheme(.aurora) }
#Preview("Settings · light") { SettingsRootView(socialModel: CircleViewModel()).circlePreviewTheme(.daylight) }

private struct TrollConsentCard: View {
    @Bindable var model: CircleViewModel
    var body: some View {
        Toggle("Allow my friends to post me on the Troll Wall", isOn: Binding(
            get: { model.allowTrollPosts },
            set: { allowed in Task { await model.updateConsent(allowed) } }))
            .disabled(model.consentPending || (model.isLive && !model.hasLoaded)).padding(18).circleSurface(radius: 22)
    }
}
#Preview("Consent · dark") { TrollConsentCard(model: CircleViewModel()).padding().circlePreviewTheme(.aurora) }
#Preview("Consent · light") { TrollConsentCard(model: CircleViewModel()).padding().circlePreviewTheme(.daylight) }
