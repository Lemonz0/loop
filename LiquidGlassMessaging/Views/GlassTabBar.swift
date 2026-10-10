import SwiftUI
import UIKit

/// System iOS 26 TabView owns the floating Liquid Glass tab bar.
struct GlassTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chatStore = AppEnvironment.shared.chatStore
    @State private var metrics = ConversationDockMetrics()
    @State private var keyboardIsVisible = false
    private var activeRoom: ChatRoom? {
        guard let active = chatStore.activeRoom else { return nil }
        return chatStore.rooms.first(where: { $0.id == active.id }) ?? active
    }
    @State private var model: CircleViewModel
    init(preview: Bool = false) { _model = State(initialValue: preview ? CircleViewModel() : CircleViewModel.production()) }
    @State private var selectedTab = CircleTab.home
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: CircleTab.home) { HomeView(model: model) }
            Tab("Chats", systemImage: "bubble.left.and.bubble.right", value: CircleTab.chats) {
                MessagesView().toolbar(activeRoom == nil ? .visible : .hidden, for: .tabBar)
                    .background { ConversationDockMeasurement(metrics: metrics).frame(width: 0, height: 0).allowsHitTesting(false) }
            }
            Tab("Settings", systemImage: "gearshape", value: CircleTab.settings) { SettingsRootView(socialModel: model) }
            Tab("Profile", systemImage: "person.crop.circle", value: CircleTab.profile) { ProfileView() }
        }
        .environment(\.conversationDockContext, metrics)
        .environment(\.usesSharedConversationDock, true)
        .environment(\.conversationDockHeight, metrics.height)
        .tabBarMinimizeBehavior(.onScrollDown)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let room = activeRoom, let input = metrics.input {
                ChatInputDockView(text: input, room: room,
                    onSendText: { text in
                        ProMotionEngine.shared.boostTo120(duration: 1.5)
                        guard let user = AuthSessionManager.shared.currentSession?.user else { return }
                        chatStore.sendTextMessage(text, in: room, currentUserId: user.id, currentUserName: user.displayName)
                    }, onSendAttachment: { attachment in
                        ProMotionEngine.shared.boostTo120(duration: 2.0)
                        guard let user = AuthSessionManager.shared.currentSession?.user else { return }
                        chatStore.sendMediaMessage(attachment, in: room, currentUserId: user.id, currentUserName: user.displayName)
                    }, onTypingChanged: { typing in
                        if typing { ProMotionEngine.shared.boostTo120(duration: 1.2) }
                        chatStore.emitTyping(isTyping: typing, in: room)
                    })
                    .environment(\.conversationDockHeight, metrics.height)
                    .offset(y: keyboardIsVisible ? 0 : metrics.bottomOffset)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardIsVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardIsVisible = false }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.35), value: activeRoom?.id)
        .sensoryFeedback(.success, trigger: model.feedback)
        .modifier(CircleErrorAlert(model: model))
    }
}

private enum CircleTab: Hashable { case home, chats, settings, profile }

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()
                ScrollView { ProfileCard().padding(20) }
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview("Tabs · dark") { GlassTabBar(preview: true).circlePreviewTheme(.aurora) }
#Preview("Tabs · light") { GlassTabBar(preview: true).circlePreviewTheme(.daylight) }
#Preview("Profile · dark") { ProfileView().circlePreviewTheme(.aurora) }
#Preview("Profile · light") { ProfileView().circlePreviewTheme(.daylight) }
