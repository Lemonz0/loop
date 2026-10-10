import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Main conversation view styled with fluid liquid-glass materials, ambient backdrop glow,
/// and smooth spring-animated message delivery.
@MainActor
public struct ChatRoomView: View {
    @Environment(\.conversationDockContext) private var dockContext
    @Environment(\.usesSharedConversationDock) private var usesSharedDock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    private let initialRoom: ChatRoom
    public var room: ChatRoom { chatStore.rooms.first(where: { $0.id == initialRoom.id }) ?? initialRoom }
    @Bindable public var chatStore: ChatStore
    @Bindable public var callManager = WebRTCManager.shared

    @State private var inputText: String = ""
    @State private var isCallPresented: Bool = false
    @State private var selectedWallpaperItem: PhotosPickerItem? = nil
    @State private var isShowingWallpaperPicker: Bool = false
    @State private var showsWallpaperActions = false
    @State private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    public init(room: ChatRoom, chatStore: ChatStore) {
        self.initialRoom = room
        self.chatStore = chatStore
    }

    public var body: some View {
        ZStack {
            // Ambient moving background adapting to room theme / wallpaper
            AmbientGlowBackground(roomId: room.id)

            VStack(spacing: 0) {
                // Messages Scrollable Feed
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            let messages = chatStore.messagesByRoomId[room.id] ?? []

                            // Encryption status disclaimer pill
                            Text("Direct Closed Circle • Instant Sync")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.secondaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .liquidGlassPill(specularIntensity: 0.25, strokeWidth: 0.8)
                                .padding(.top, 12)
                                .padding(.bottom, 6)

                            ForEach(messages) { message in
                                MessageBubbleView(message: message, isGroup: room.isGroup)
                                    .id(message.id)
                                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                            }

                            // Live typing indicator bubble
                            if let typingUsers = chatStore.typingUsersByRoomId[room.id], !typingUsers.isEmpty {
                                HStack {
                                    LiveTypingIndicatorView(userNames: Array(typingUsers))
                                        .padding(.leading, 16)
                                        .transition(.scale.combined(with: .opacity))
                                    Spacer()
                                }
                                .padding(.top, 4)
                                .id("typing_indicator")
                            }

                            // Bottom spacer for floating input bar
                            Color.clear
                                .frame(height: 70)
                                .id("bottom_anchor")
                        }
                        .padding(.vertical, 8)
                        .proMotionAdaptiveScroll(coordinateSpaceName: "chat_room_scroll_\(room.id)")
                    }
                    .contextMenu {
                        Button("Set loop wallpaper", systemImage: "photo") { isShowingWallpaperPicker = true }
                        Button("Reset wallpaper", systemImage: "arrow.counterclockwise", role: .destructive) { Task { await themeManager.resetRoomTheme(for: room.id, chatStore: chatStore) } }
                    }
                    .coordinateSpace(name: "chat_room_scroll_\(room.id)")
                    .safeAreaBar(edge: .top, spacing: 0) {
                        GlassEffectContainer(spacing: 14) { chatHeader }
                    }
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .onChange(of: chatStore.messagesByRoomId[room.id]?.count) { _, _ in
                        ProMotionEngine.shared.boostTo120(duration: 1.5)
                        withAnimation(GlassTheme.fluidSpring) {
                            proxy.scrollTo("bottom_anchor", anchor: .bottom)
                        }
                    }
                    .onChange(of: chatStore.typingUsersByRoomId[room.id]?.count) { _, count in
                        if (count ?? 0) > 0 {
                            ProMotionEngine.shared.boostTo120(duration: 1.0)
                            withAnimation(GlassTheme.fluidSpring) {
                                proxy.scrollTo("typing_indicator", anchor: .bottom)
                            }
                        }
                    }
                }

                // Standalone previews keep their composer; the app anchors it at tab level.
                if !usesSharedDock {
                ChatInputDockView(
                    text: $inputText,
                    room: room,
                    onSendText: { text in
                        ProMotionEngine.shared.boostTo120(duration: 1.5)
                        let myId = AuthSessionManager.shared.currentSession?.user.id ?? "user_me"
                        let myName = AuthSessionManager.shared.currentSession?.user.displayName ?? "Friend"
                        chatStore.sendTextMessage(text, in: room, currentUserId: myId, currentUserName: myName)
                    },
                    onSendAttachment: { attachment in
                        ProMotionEngine.shared.boostTo120(duration: 2.0)
                        let myId = AuthSessionManager.shared.currentSession?.user.id ?? "user_me"
                        let myName = AuthSessionManager.shared.currentSession?.user.displayName ?? "Friend"
                        chatStore.sendMediaMessage(attachment, in: room, currentUserId: myId, currentUserName: myName)
                    },
                    onTypingChanged: { isTyping in
                        if isTyping {
                            ProMotionEngine.shared.boostTo120(duration: 1.2)
                        }
                        chatStore.emitTyping(isTyping: isTyping, in: room)
                    }
                )
                .padding(.bottom, 8)
                }
            }
        }
        #if os(iOS)
        .background { ConversationBackSwipe().frame(width: 0, height: 0).allowsHitTesting(false) }
        #endif
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        #if os(iOS)
        .photosPicker(isPresented: $isShowingWallpaperPicker, selection: $selectedWallpaperItem, matching: .images)
        #endif
        .onAppear {
            if usesSharedDock { dockContext?.input = $inputText }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.35)) { chatStore.activeRoom = room }
        }
        .onDisappear {
            if chatStore.activeRoom?.id == room.id {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.35)) { chatStore.activeRoom = nil; dockContext?.input = nil }
            }
        }
    }

    private func startCall(video: Bool) {
        Task { await callManager.startCall(roomId: room.id, roomName: room.name, isVideo: video) }
    }
    // MARK: - Header

    // The native safeAreaBar owns the progressive top-edge blur/fade. No extra platter.
    private var chatHeader: some View {
        HStack(spacing: 12) {
            // Back Button
            Button {
                HapticFeedback.soft()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("Back to Chats")

            // Room Title & Status
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.tail)

                HStack(spacing: 5) {
                    Circle()
                        .fill(theme.success)
                        .frame(width: 7, height: 7)

                    Text(room.isGroup ? "\(chatStore.onlineCount(in: room)) online" : (room.participantIds.contains(where: { $0 != AuthSessionManager.shared.currentSession?.user.id && chatStore.presenceByUserId[$0]?.isOnline == true }) ? "Online" : "Offline")).lineLimit(1)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)

            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    Button { startCall(video: true) } label: { Image(systemName: "video.fill").frame(width: 44, height: 44) }.accessibilityLabel("Video call")
                    Button { startCall(video: false) } label: { Image(systemName: "phone.fill").frame(width: 44, height: 44) }.accessibilityLabel("Voice call")
                }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: Capsule())
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: selectedWallpaperItem) {
            guard let item = selectedWallpaperItem else { return }
            Task {
                #if canImport(UIKit)
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await themeManager.setCustomWallpaper(
                        for: room.id,
                        image: image,
                        chatStore: chatStore,
                        uploader: AppEnvironment.shared.mediaUploadManager
                    )
                }
                #endif
            }
        }
    }
}

#Preview("Conversation edge · dark") {
    let store = ChatStore(preview: true)
    NavigationStack { ChatRoomView(room: store.rooms[0], chatStore: store) }.circlePreviewTheme(.aurora)
}
#Preview("Conversation edge · light") {
    let store = ChatStore(preview: true)
    NavigationStack { ChatRoomView(room: store.rooms[0], chatStore: store) }.circlePreviewTheme(.daylight)
}
