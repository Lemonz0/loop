import SwiftUI

/// Settings container view adopting Apple's native iOS 26 Liquid Glass SDK.
/// Hosts the modular SettingsRootView with category sub-pages and live user telemetry.
@MainActor
public struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    public var isModal: Bool

    public init(isModal: Bool = false) {
        self.isModal = isModal
    }

    public var body: some View {
        SettingsRootView(isModal: isModal)
    }
}

// MARK: - Preview

#Preview("Settings host · dark") { SettingsView().circlePreviewTheme(.aurora) }
#Preview("Settings host · light") { SettingsView().circlePreviewTheme(.daylight) }
