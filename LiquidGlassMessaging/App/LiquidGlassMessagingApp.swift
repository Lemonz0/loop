import SwiftUI

/// Main container view for the Liquid Glass messaging experience.
@MainActor
public struct LiquidGlassMessagingAppView: View {
    @State private var environment = AppEnvironment.shared
    @State private var authManager = AuthSessionManager.shared
    @State private var callManager = WebRTCManager.shared
    @State private var themeManager = ThemeManager.shared
    
    public init() {}
    
    public var body: some View {
        Group {
            if authManager.isAuthenticated {
                GlassTabBar()
            } else if authManager.isValidating {
                ZStack { AmbientGlowBackground(); ProgressView("Checking your session…") }
            } else {
                InviteAuthView(onSuccess: {})
            }
        }
            .environment(\.appTheme, AppTheme(preset: themeManager.activePreset))
            .environment(\.colorScheme, AppTheme(preset: themeManager.activePreset).colorScheme)
            .preferredColorScheme(AppTheme(preset: themeManager.activePreset).colorScheme)
            .tint(AppTheme(preset: themeManager.activePreset).accent)
            .task { await authManager.validateSavedSession(serverURL: environment.serverBaseURL) }
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated { environment.activateSessionIfAvailable() }
                else { environment.chatStore.reset() }
            }
            .onChange(of: authManager.circles.map(\.roomId)) { _, _ in
                if authManager.isAuthenticated { environment.activateSessionIfAvailable() }
            }
            .fullScreenCover(isPresented: Binding(get: { callManager.callStatus != .idle && callManager.callStatus != .ended }, set: { if !$0 { Task { await callManager.hangup() } } })) { CallOverlayView().environment(\.appTheme, AppTheme(preset: themeManager.activePreset)).preferredColorScheme(AppTheme(preset: themeManager.activePreset).colorScheme).tint(AppTheme(preset: themeManager.activePreset).accent).interactiveDismissDisabled() }
            .alert("Call", isPresented: Binding(get: { callManager.lastError != nil }, set: { if !$0 { callManager.lastError = nil } })) { Button("OK") { callManager.lastError = nil } } message: { Text(callManager.lastError ?? "") }
            .onAppear {
                ProMotionManager.shared.start()
            }
    }
}

#if !SWIFT_PACKAGE
@main
struct LiquidGlassMessagingApp: App {
    var body: some Scene {
        WindowGroup {
            LiquidGlassMessagingAppView()
        }
    }
}
#endif
