import SwiftUI

/// Main conversations directory displaying 1-on-1 chats and named group rooms
/// styled with authentic Apple iOS 26 Liquid Glass controls and seamless list rows.
@MainActor
public struct ChatRoomListView: View {
    @Environment(\.appTheme) private var theme
    @Bindable public var chatStore: ChatStore
    @State private var searchText: String = ""
    @State private var selectedRoom: ChatRoom?

    public init(chatStore: ChatStore) {
        self.chatStore = chatStore
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Ambient luminous background
                AmbientGlowBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        // Liquid Glass Search Capsule
                        searchBar
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        // Active Friends Horizontal Presence Dock
                        presenceHorizontalDock
                            .padding(.top, 2)

                        // Seamless Chat Rows List (WhatsApp Reference)
                        LazyVStack(spacing: 14) {
                            ForEach(Array(filteredRooms.enumerated()), id: \.element.id) { index, room in
                                NavigationLink(destination: ChatRoomView(room: room, chatStore: chatStore)) {
                                    ChatRowView(room: room)
                                }
                                .buttonStyle(.plain)

                                if index < filteredRooms.count - 1 {
                                    Divider()
                                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .padding(.leading, 78)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.bottom, 96) // Allows scrolling underneath the floating glass dock
                    .proMotionAdaptiveScroll(coordinateSpaceName: "room_list_scroll")
                }
                .coordinateSpace(name: "room_list_scroll")
            }
            .navigationTitle("Messages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticFeedback.soft()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                }

                ToolbarItem(placement: .topBarTrailing) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 6) {
                            Button {
                                HapticFeedback.soft()
                            } label: {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: Circle())

                            Button {
                                HapticFeedback.soft()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive().tint(theme.success), in: Circle())
                        }
                        .padding(4)
                    }
                    .glassEffect(.regular, in: Capsule())
                }
            }
            #endif
        }
    }

    // MARK: - Liquid Glass Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(.primary)

            TextField("Ask AI or Search messages...", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Horizontal Presence Dock

    private var presenceHorizontalDock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(chatStore.presenceByUserId.values)) { presence in
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottomTrailing) {
                            Text(String(presence.displayName.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .frame(width: 50, height: 50)
                                .glassEffect(.regular, in: Circle()).profileEntry(presence.userId, name: presence.displayName, source: "contacts")

                            // Online indicator badge
                            if presence.isOnline {
                                Circle()
                                    .fill(theme.success)
                                    .frame(width: 12, height: 12)

                                    .offset(x: 1, y: 1)
                            }
                        }

                        Text(presence.displayName).profileEntry(presence.userId, name: presence.displayName, source: "contacts")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(width: 58).profileEntry(presence.userId, name: presence.displayName, source: "contacts")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Filter

    private var filteredRooms: [ChatRoom] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return chatStore.rooms
        } else {
            return chatStore.rooms.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// MARK: - Seamless Chat Row View (WhatsApp Reference)

@MainActor
private struct ChatRowView: View {
    @Environment(\.appTheme) private var theme
    let room: ChatRoom
    private var peerID: String? { room.participantIds.first { $0 != AuthSessionManager.shared.currentSession?.user.id } }

    var body: some View {
        HStack(spacing: 14) {
            // Room Avatar
            ZStack(alignment: .bottomTrailing) {
                Text(room.isGroup ? "👥" : String(room.name.prefix(1)).uppercased())
                    .font(.system(size: room.isGroup ? 20 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: Circle()).profileEntry(peerID ?? "", name: room.name, source: "chat_search", enabled: !room.isGroup && peerID != nil)

                // Status dot
                Circle()
                    .fill(theme.success)
                    .frame(width: 12, height: 12)

                    .offset(x: 1, y: 1)
            }

            // Content
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(room.name).profileEntry(peerID ?? "", name: room.name, source: "chat_search", enabled: !room.isGroup && peerID != nil)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(formatTime(room.updatedAt))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(room.unreadCount > 0 ? theme.success : theme.secondaryText)
                }

                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.accent)

                    Text(room.lastMessage?.content.isEmpty == false ? (room.lastMessage?.content ?? "No messages yet") : "Attached media")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    if room.unreadCount > 0 {
                        Text("\(room.unreadCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
