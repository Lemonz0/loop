import SwiftUI

/// Connection status and recovery using Liquid Glass.
@MainActor
public struct ConnectionSettingsView: View {
    @Environment(\.appTheme) private var theme
    @State private var chatStore = AppEnvironment.shared.chatStore
    @State private var isReconnecting: Bool = false
    @State private var logger = AppLogger.shared

    public init() {}

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Connection Health Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CONNECTION HEALTH")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.leading, 6)

                        GlassEffectContainer(spacing: 14) {
                            VStack(spacing: 14) {
                                // Status Card
                                LabeledContent("Status") {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(connectionColor)
                                            .frame(width: 8, height: 8)
                                        Text(connectionLabel)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(connectionColor)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                                // Latency Card
                                if case .connected = chatStore.connectionState {
                                    LabeledContent("Latency") {
                                        Text("\(chatStore.pingLatencyMs) ms")
                                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                }
                            }
                        }
                    }

                    // Connection recovery
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECONNECT")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.leading, 6)

                        GlassEffectContainer(spacing: 14) {
                            VStack(spacing: 14) {
                                // Reconnect Button
                                Button {
                                    reconnect()
                                } label: {
                                    HStack(spacing: 10) {
                                        Spacer()
                                        if isReconnecting {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                        }
                                        Text("Reconnect")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(theme.accent)
                                .disabled(isReconnecting)
                            }
                        }
                    }

                    // Footer explanatory card
                    HStack(spacing: 12) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.secondaryText)
                        Text("Reconnect if your messages aren’t updating.")
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
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectionColor: Color {
        switch chatStore.connectionState {
        case .connected: return theme.success
        case .connecting, .reconnecting: return theme.warning
        case .disconnected: return theme.destructive
        }
    }

    private var connectionLabel: String {
        switch chatStore.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Disconnected"
        }
    }

    private func reconnect() {
        isReconnecting = true
        HapticFeedback.soft()

        AppEnvironment.shared.reconnectServer()
        logger.info(.network, "Reconnecting to Loop")

        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            isReconnecting = false
        }
    }
}

// MARK: - Preview

#Preview("Connection · dark") {
    NavigationStack { ConnectionSettingsView() }.circlePreviewTheme(.aurora)
}
#Preview("Connection · light") {
    NavigationStack { ConnectionSettingsView() }.circlePreviewTheme(.daylight)
}
