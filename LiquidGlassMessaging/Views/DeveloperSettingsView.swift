import SwiftUI

/// Focused sub-page for real-time developer diagnostics, console logs, and event telemetry export using Liquid Glass.
@MainActor
public struct DeveloperSettingsView: View {
    @Environment(\.appTheme) private var theme
    @State private var logger = AppLogger.shared
    @State private var showLogConsole: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Diagnostics Overview Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DIAGNOSTICS OVERVIEW")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.leading, 6)

                        GlassEffectContainer(spacing: 14) {
                            Text("Real-time logging records WebSocket network cycles, media compression runs, and WebRTC call states.")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }

                    // Telemetry Tools Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TELEMETRY TOOLS")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.leading, 6)

                        GlassEffectContainer(spacing: 14) {
                            VStack(spacing: 14) {
                                // Live Console Button
                                Button {
                                    HapticFeedback.selection()
                                    showLogConsole = true
                                } label: {
                                    HStack(spacing: 10) {
                                        Spacer()
                                        Image(systemName: "terminal.fill")
                                            .font(.system(size: 16))
                                        Text("Open Live Console")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(theme.accent)

                                // Export Logs Button
                                if let logFile = logger.exportFileURL() {
                                    ShareLink(item: logFile) {
                                        HStack(spacing: 10) {
                                            Spacer()
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 16))
                                            Text("Export Diagnostic Logs")
                                                .font(.system(size: 16, weight: .semibold))
                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 52)
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                        }
                    }

                    // Footer explanatory card
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.secondaryText)
                        Text("Exported logs contain sanitized network timestamps and error traces for performance profiling.")
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
        .navigationTitle("Developer & Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogConsole) {
            LogConsoleView()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeveloperSettingsView()
    }

}
