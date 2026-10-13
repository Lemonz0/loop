import SwiftUI

// MARK: - Sample Models

public struct Contact: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let initials: String
    public let isOnline: Bool
    public let user: User?
    public init(id: String = UUID().uuidString, name: String, initials: String, isOnline: Bool, user: User? = nil) {
        self.id = id; self.name = name; self.initials = initials; self.isOnline = isOnline; self.user = user
    }

    public static let sampleContacts: [Contact] = [
        Contact(name: "Elena", initials: "E", isOnline: true),
        Contact(name: "Alex", initials: "A", isOnline: true)
    ]
}

public struct Chat: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var title: String
    public var isGroup: Bool
    public var initials: String
    public var avatarURL: URL?
    public var timestamp: String
    public var subtitle: String
    public var isVerifiedOrRead: Bool
    public var unreadCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        isGroup: Bool,
        initials: String,
        avatarURL: URL? = nil,
        timestamp: String,
        subtitle: String,
        isVerifiedOrRead: Bool,
        unreadCount: Int
    ) {
        self.id = id
        self.title = title
        self.isGroup = isGroup
        self.initials = initials
        self.avatarURL = avatarURL
        self.timestamp = timestamp
        self.subtitle = subtitle
        self.isVerifiedOrRead = isVerifiedOrRead
        self.unreadCount = unreadCount
    }

    public static let sampleChats: [Chat] = [
        Chat(
            title: "The Inner Circle ✨",
            isGroup: true,
            initials: "IC",
            timestamp: "10:42",
            subtitle: "Attached media",
            isVerifiedOrRead: true,
            unreadCount: 0
        ),
        Chat(
            title: "Elena Rostova",
            isGroup: false,
            initials: "E",
            timestamp: "09:42",
            subtitle: "Attached media",
            isVerifiedOrRead: true,
            unreadCount: 0
        ),
        Chat(
            title: "Alex Morgan",
            isGroup: false,
            initials: "A",
            timestamp: "Yesterday",
            subtitle: "Check out the new liquid glass!",
            isVerifiedOrRead: false,
            unreadCount: 1
        )
    ]
}

public enum ChatFilter: String, CaseIterable, Identifiable {
    case all = "All Messages"
    case directMessages = "Direct Messages"
    case groups = "Groups"
    case unread = "Unread Only"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "bubble.left.and.bubble.right.fill"
        case .directMessages: return "person.fill"
        case .groups: return "person.3.fill"
        case .unread: return "circle.badge.plus.fill"
        }
    }
}

public enum ChatSortOrder: String, CaseIterable, Identifiable {
    case recent = "Recent Activity"
    case alphabetical = "Alphabetical (A–Z)"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .recent: return "clock.fill"
        case .alphabetical: return "textformat.abc"
        }
    }
}

public enum TabItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case messages = "Messages"
    case settings = "Settings"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .home: return "house.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Native iOS 26 Messages Screen

public struct MessagesView: View {
    @Environment(\.appTheme) private var theme
    @State private var path: [Chat] = []
    @State private var openingContact: String?
    @State private var selectedTab: TabItem = .messages
    @State private var chatStore = AppEnvironment.shared.chatStore
    @State private var auth = AuthSessionManager.shared
    private var chats: [Chat] {
        chatStore.rooms.compactMap { room in
            guard let id = UUID(uuidString: room.id) else { return nil }
            return Chat(id: id, title: room.name, isGroup: room.isGroup, initials: String(room.name.prefix(2)).uppercased(),
                        avatarURL: room.avatarURL, timestamp: room.lastMessage?.timestamp.formatted(date: .omitted, time: .shortened) ?? "",
                        subtitle: room.lastMessage?.content.isEmpty == false ? room.lastMessage!.content : room.lastMessage == nil ? "Start a conversation" : "Attached media",
                        isVerifiedOrRead: room.lastMessage?.status == .read, unreadCount: room.unreadCount)
        }
    }
    @State private var activeFilter: ChatFilter = .all
    @State private var sortOrder: ChatSortOrder = .recent

    @State private var renameCircle: AccountCircle?
    @State private var loopName = ""
    @State private var showRename = false
    @State private var showAddUserSheet = false
    @State private var showNewGroupSheet = false
    @State private var showDirectPicker = false
    @State private var showArchivedSheet = false
    @State private var showContacts = false
    @State private var showCallHistory = false

    @Namespace private var glassNamespace

    public init() {}

    private var filteredChats: [Chat] {
        var result = chats

        // 1. Filter by category
        switch activeFilter {
        case .all:
            break
        case .directMessages:
            result = result.filter { !$0.isGroup }
        case .groups:
            result = result.filter { $0.isGroup }
        case .unread:
            result = result.filter { $0.unreadCount > 0 }
        }

        // 3. Sort order
        switch sortOrder {
        case .recent:
            result.sort { a, b in
                let left = chatStore.rooms.first { UUID(uuidString: $0.id) == a.id }?.updatedAt ?? .distantPast
                let right = chatStore.rooms.first { UUID(uuidString: $0.id) == b.id }?.updatedAt ?? .distantPast
                return left > right
            }
        case .alphabetical:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }

        return result
    }

    public var body: some View {
        messagesNavigationStack
    }

    // MARK: - Messages Navigation Stack with Native Liquid Glass

    private var messagesNavigationStack: some View {
        NavigationStack(path: $path) {
            ZStack {
                // Plain colorful background without any artificial .blur() or fake materials
                // The native Liquid Glass engine uses this background for optical refraction
                plainColorfulBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Dedicated Single-Layer Liquid Glass Header
                    // Replaces the system toolbar to eliminate double backgrounds completely
                    glassHeader

                    // Scrollable Feed
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Large "Messages" Title
                            HStack {
                                Text("Messages")
                                    .font(.system(size: 34, weight: .bold, design: .default))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        // Active Filter Pill Banner
                        if activeFilter != .all {
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: activeFilter.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(activeFilter.rawValue)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    Button {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                            activeFilter = .all
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .glassEffect(.regular.interactive().tint(theme.glassTint), in: Capsule())

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }

                        // Online Contacts Horizontal Row
                        OnlineContactsRow(contacts: chatStore.presenceByUserId.values.filter { $0.isOnline && $0.userId != auth.currentSession?.user.id }.sorted { $0.displayName < $1.displayName }.map {
                            Contact(id: $0.userId, name: chatStore.memberProfiles[$0.userId]?.name ?? $0.displayName, initials: String($0.displayName.prefix(1)).uppercased(), isOnline: true, user: chatStore.memberProfiles[$0.userId])
                        }, onOpen: { contact in openContact(contact) })
                        .disabled(openingContact != nil)
                        if openingContact != nil { ProgressView("Opening private chat…") }

                        // Chat Cards Feed
                        if filteredChats.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "tray")
                                    .font(.system(size: 32))
                                    .foregroundStyle(theme.secondaryText)
                                    .padding(.top, 24)
                                Text("No Conversations Found")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("No chats match the selected filter.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .padding(.horizontal, 20)
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(filteredChats) { chat in
                                    NavigationLink(value: chat) {
                                        ChatRowCard(chat: chat)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if let circle = auth.circles.first(where: { UUID(uuidString: $0.roomId) == chat.id }) {
                                            Button("Edit loop name", systemImage: "pencil") { renameCircle = circle; loopName = circle.name; showRename = true }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                    }
                    .scrollEdgeEffectStyle()
                }
            }
        }
        .onChange(of: ProfilePresentation.shared.destination?.id) { _, _ in openProfileDestination() }
        .onAppear { openProfileDestination() }
        .sheet(isPresented: $showContacts) { ProfileDirectoryView(room: nil) }
        .sheet(isPresented: $showCallHistory) { LoopCallHistoryView() }
        .refreshable { _ = await auth.validateSavedSession() }
        .alert("Edit loop name", isPresented: $showRename) {
            TextField("Loop name", text: $loopName)
            Button("Save") { if let circle = renameCircle { Task { await auth.renameCircle(id: circle.id, name: loopName) } } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Account", isPresented: Binding(get: { auth.lastError != nil }, set: { if !$0 { auth.lastError = nil } })) {
            Button("OK") { auth.lastError = nil }
        } message: { Text(auth.lastError ?? "") }
        .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $showAddUserSheet) {
                AccountInviteView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showDirectPicker) {
                DirectMessagePicker(users: chatStore.memberProfiles.values.filter { $0.id != auth.currentSession?.user.id }.sorted { $0.name < $1.name },
                    onOpen: { user in
                        if let room = await chatStore.openDirect(userID: user.id), let id = UUID(uuidString: room.id) {
                            path.append(Chat(id: id, title: room.name, isGroup: false, initials: String(room.name.prefix(1)), avatarURL: room.avatarURL,
                                timestamp: "", subtitle: "", isVerifiedOrRead: false, unreadCount: 0))
                            showDirectPicker = false; return true
                        }
                        return false
                    })
            }
            .sheet(isPresented: $showNewGroupSheet) {
                NewGroupSheetView(isPresented: $showNewGroupSheet) { name in
                    let success = await auth.createCircle(name: name)
                    if success { activeFilter = .all; sortOrder = .recent }
                    return success
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showArchivedSheet) {
                ArchivedChatsSheetView(isPresented: $showArchivedSheet)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(for: Chat.self) { chat in
                if let room = chatStore.rooms.first(where: { UUID(uuidString: $0.id) == chat.id }) {
                    ChatRoomView(room: room, chatStore: chatStore)
                }
            }
        }
    }

    private func openProfileDestination() {
        guard let room = ProfilePresentation.shared.destination, let id = UUID(uuidString: room.id) else { return }
        showDirectPicker = false; showContacts = false; showCallHistory = false
        if chatStore.activeRoom?.id != room.id {
            path = [Chat(id: id, title: room.name, isGroup: false, initials: String(room.name.prefix(1)), avatarURL: room.avatarURL, timestamp: "", subtitle: "", isVerifiedOrRead: false, unreadCount: 0)]
        }
        ProfilePresentation.shared.destination = nil
    }

    // MARK: - Dedicated Single-Layer Liquid Glass Header (Zero Double Backgrounds)

    private var glassHeader: some View {
        HStack {
            // Top Left: Reorganize & Filter Menu (EXACTLY ONE background, pure Liquid Glass circle)
            Menu {
                Button("Contacts & search", systemImage: "person.2") { showContacts = true }
                Button("Call history", systemImage: "phone") { showCallHistory = true }
                Section("Filter") {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            activeFilter = .all
                        }
                    } label: {
                        Label("All Messages", systemImage: activeFilter == .all ? "checkmark.circle.fill" : "bubble.left.and.bubble.right")
                    }

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            activeFilter = .directMessages
                        }
                    } label: {
                        Label("Direct Messages", systemImage: activeFilter == .directMessages ? "checkmark.circle.fill" : "person.fill")
                    }

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            activeFilter = .groups
                        }
                    } label: {
                        Label("Groups", systemImage: activeFilter == .groups ? "checkmark.circle.fill" : "person.3.fill")
                    }

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            activeFilter = .unread
                        }
                    } label: {
                        Label("Unread Only", systemImage: activeFilter == .unread ? "checkmark.circle.fill" : "circle.badge.plus")
                    }
                }

                Section("Sort Order") {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            sortOrder = .recent
                        }
                    } label: {
                        Label("Recent Activity", systemImage: sortOrder == .recent ? "checkmark" : "clock")
                    }

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            sortOrder = .alphabetical
                        }
                    } label: {
                        Label("Alphabetical (A–Z)", systemImage: sortOrder == .alphabetical ? "checkmark" : "textformat.abc")
                    }
                }

                Section("Actions") {
                    Button {
                        markAllAsRead()
                    } label: {
                        Label("Mark All as Read", systemImage: "checkmark.circle")
                    }

                    Button {
                        showArchivedSheet = true
                    } label: {
                        Label("Archived Chats", systemImage: "archivebox")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Top Right: Single "+" Button (EXACTLY ONE background, pure Liquid Glass circle tinted blue)
            Menu {
                Button("Direct message", systemImage: "bubble.left.and.bubble.right") { showDirectPicker = true }
                Button {
                    showAddUserSheet = true
                } label: {
                    Label("Join or invite friends", systemImage: "person.badge.plus")
                }

                Button {
                    showNewGroupSheet = true
                } label: {
                    Label("New Group", systemImage: "person.3.fill")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive().tint(theme.glassTint), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Chat Management Actions

    private func markAllAsRead() {
        for index in chatStore.rooms.indices { chatStore.rooms[index].unreadCount = 0 }
    }
    private func openContact(_ contact: Contact) {
        guard openingContact == nil else { return }; openingContact = contact.id
        Task {
            defer { openingContact = nil }
            if let room = await chatStore.openDirect(userID: contact.id), let id = UUID(uuidString: room.id) {
                let chat = Chat(id: id, title: room.name, isGroup: false, initials: String(room.name.prefix(1)), avatarURL: room.avatarURL,
                    timestamp: "", subtitle: "", isVerifiedOrRead: false, unreadCount: 0)
                path.append(chat)
            }
        }
    }

    // MARK: - Plain Colorful Background (Zero Fake Blur / Material)

    private var plainColorfulBackground: some View {
        AmbientGlowBackground()
    }
}

// MARK: - Subview: OnlineContactsRow

public struct OnlineContactsRow: View {
    @Environment(\.appTheme) private var theme
    public let contacts: [Contact]
    public var onOpen: (Contact) -> Void

    public init(contacts: [Contact], onOpen: @escaping (Contact) -> Void = { _ in }) {
        self.contacts = contacts; self.onOpen = onOpen
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(contacts) { contact in
                    VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        // GlassEffectContainer prevents stacking glass on glass without a container
                        GlassEffectContainer(spacing: 2) {
                            ZStack(alignment: .bottomTrailing) {
                                // Avatar circle with native Liquid Glass
                                if let user = contact.user { CircleAvatar(user: user, size: 58) }
                                else {
                                Text(contact.initials)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .frame(width: 58, height: 58)
                                    .glassEffect(
                                        .regular.tint(theme.glassTint),
                                        in: Circle()
                                    )
                                }

                                // Small green glass dot for online status
                                if contact.isOnline {
                                    Circle()
                                        .frame(width: 14, height: 14)
                                        .glassEffect(
                                            .regular.tint(theme.success.opacity(0.08)),
                                            in: Circle()
                                        )
                                        .offset(x: 2, y: 2)
                                }
                            }
                        }

                        Text(contact.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                    }
                    }.profileEntry(contact.id, name: contact.name, source: "contacts")
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Subview: ChatRowCard

public struct ChatRowCard: View {
    private var profileRoom: ChatRoom? { AppEnvironment.shared.chatStore.rooms.first { UUID(uuidString: $0.id) == chat.id } }
    private var peerID: String? { profileRoom?.participantIds.first { $0 != AuthSessionManager.shared.currentSession?.user.id } }
    @Environment(\.appTheme) private var theme
    public let chat: Chat

    public init(chat: Chat) {
        self.chat = chat
    }

    public var body: some View {
        // Unified glass container for avatar and card
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                // Initial or Group Icon Avatar with native Liquid Glass
                Group {
                    if chat.isGroup {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                    } else {
                        CircleAvatar(user: User(id: peerID ?? "", name: chat.title, avatarURL: chat.avatarURL, allowsTrollPosts: true), size: 50, opensProfile: peerID != nil)
                    }
                }
                .frame(width: 52, height: 52)
                .glassEffect(
                    .regular.tint(theme.glassTint),
                    in: Circle()
                )

                // Text Information
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(chat.title).profileEntry(peerID ?? "", name: chat.title, enabled: !chat.isGroup && peerID != nil)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(chat.timestamp)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(theme.secondaryText)
                    }

                    HStack(spacing: 6) {
                        if chat.isVerifiedOrRead {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(theme.accent)
                        }

                        Text(chat.subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }
}

// MARK: - Subview: AddUserSheetView

public struct AddUserSheetView: View {
    @Environment(\.appTheme) private var theme
    @Binding public var isPresented: Bool
    public var onAddUser: (String) -> Void

    @State private var usernameInput: String = ""
    @State private var errorMessage: String? = nil

    // Quick suggested handles
    private let suggestedUsers = [
        ("Sophia Chen", "sophia_c", "SC"),
        ("Marcus Vance", "marcus_v", "MV"),
        ("David Miller", "david_m", "DM")
    ]

    public init(isPresented: Binding<Bool>, onAddUser: @escaping (String) -> Void) {
        self._isPresented = isPresented
        self.onAddUser = onAddUser
    }

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            VStack(spacing: 0) {
                // Top close button header (Single-layer Liquid Glass circle, zero UIKit platter)
                HStack {
                    Spacer()
                    Button {
                        HapticFeedback.soft()
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(spacing: 22) {
                    // Header icon and description
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 68, height: 68)
                            .glassEffect(.regular.tint(theme.glassTint), in: Circle())
                            .padding(.top, 2)

                        Text("Add Contact")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Enter a unique username to start messaging directly.")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Username Input Field Capsule
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text("@")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.accent)

                            TextField("username", text: $usernameInput)
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            if !usernameInput.isEmpty {
                                Button {
                                    usernameInput = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(theme.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .glassEffect(.regular, in: Capsule())

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.destructive)
                                .padding(.leading, 12)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Suggested Contacts Pills
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Suggestions")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, 24)

                        HStack(spacing: 10) {
                            ForEach(suggestedUsers, id: \.1) { name, handle, initials in
                                Button {
                                    usernameInput = handle
                                    errorMessage = nil
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(initials)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.primary)
                                            .frame(width: 26, height: 26)
                                            .glassEffect(.regular.tint(theme.glassTint), in: Circle())

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(name)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text("@\(handle)")
                                                .font(.system(size: 10))
                                                .foregroundStyle(theme.secondaryText)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer()

                    // Action Button
                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Start Conversation")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? .regular
                            : .regular.interactive().tint(theme.glassTint),
                        in: Capsule()
                    )
                    .disabled(usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func submit() {
        let cleaned = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !cleaned.isEmpty else {
            errorMessage = "Please enter a valid username."
            return
        }
        HapticFeedback.soft()
        onAddUser(cleaned)
        isPresented = false
    }
}

// MARK: - Subview: NewGroupSheetView

public struct NewGroupSheetView: View {
    @Environment(\.appTheme) private var theme
    @Binding public var isPresented: Bool
    public var onCreateGroup: (String) async -> Bool

    @State private var groupName: String = ""
    @State private var creating = false
    @State private var creationError: String?

    public init(isPresented: Binding<Bool>, onCreateGroup: @escaping (String) async -> Bool) {
        self._isPresented = isPresented
        self.onCreateGroup = onCreateGroup
    }

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            VStack(spacing: 0) {
                // Top close button header (Single-layer Liquid Glass circle, zero UIKit platter)
                HStack {
                    Spacer()
                    Button {
                        HapticFeedback.soft()
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain).disabled(creating)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 68, height: 68)
                            .glassEffect(.regular.tint(theme.glassTint), in: Circle())
                            .padding(.top, 4)

                        Text("New Group")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Create a dedicated space for your team or friends.")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(theme.accent)
                        TextField("Group name", text: $groupName).disabled(creating)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.horizontal, 20)

                    if let creationError { Text(creationError).font(.footnote).foregroundStyle(theme.destructive) }
                    Spacer()

                    Button {
                        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            HapticFeedback.soft()
                            creating = true; creationError = nil
                            Task {
                                if await onCreateGroup(name) { isPresented = false }
                                else { creationError = AuthSessionManager.shared.lastError ?? "Group could not be created."; AuthSessionManager.shared.lastError = nil }
                                creating = false
                            }
                        }
                    } label: {
                        HStack { if creating { ProgressView() }; Text(creating ? "Creating…" : "Create Group") }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? .regular
                            : .regular.interactive().tint(theme.glassTint),
                        in: Capsule()
                    )
                    .disabled(creating || groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || groupName.count > 80)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }.interactiveDismissDisabled(creating)
    }
}

// MARK: - Subview: ArchivedChatsSheetView

public struct ArchivedChatsSheetView: View {
    @Environment(\.appTheme) private var theme
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            VStack(spacing: 0) {
                // Header with Title and Single-layer Liquid Glass X button (Zero double backgrounds)
                HStack {
                    Text("Archived")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        HapticFeedback.soft()
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(spacing: 20) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(theme.accent)
                        .frame(width: 76, height: 76)
                        .glassEffect(.regular.tint(theme.glassTint), in: Circle())
                        .padding(.top, 40)

                    Text("No Archived Chats")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Conversations and groups you archive will be kept here privately.")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MessagesView()
}
