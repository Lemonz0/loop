import Foundation
import SwiftUI

/// Central observable state store for chat conversations, live presence, and WebSocket synchronization.
@Observable
@MainActor
public final class ChatStore {
    // MARK: - Published State
    public var rooms: [ChatRoom] = []
    public var activeRoom: ChatRoom?
    public var messagesByRoomId: [String: [ChatMessage]] = [:]
    public var typingUsersByRoomId: [String: Set<String>] = [:]
    public var presenceByUserId: [String: UserPresence] = [:]
    public var connectionState: WebSocketActor.ConnectionState = .disconnected
    public var pingLatencyMs: Int = 0
    public var accountRevision = 0
    public var memberProfiles: [String: User] = [:]
    public func onlineCount(in room: ChatRoom) -> Int {
        guard case .connected = connectionState else { return 0 }
        return room.participantIds.filter { presenceByUserId[$0]?.isOnline == true }.count
    }
    
    // MARK: - Dependencies
    public let webSocketActor = WebSocketActor()
    private var eventConsumerTask: Task<Void, Never>?
    private var typingResetTasks: [String: Task<Void, Never>] = [:]
    
    private var connectionMonitorTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    public init(preview: Bool = false) {
        if preview { populateInitialMockData() }
    }
    
    // MARK: - Lifecycle & Networking Bridge
    
    public func start(serverWSURL: URL, token: String?, user: UserProfile? = nil) {
        AppLogger.shared.info(.network, "Connecting to WebSocket hub: \(serverWSURL.absoluteString)")
        connectionTask?.cancel()
        connectionTask = Task {
            presenceByUserId = [:]
            await webSocketActor.disconnect()
            guard !Task.isCancelled else { return }
            let stream = await webSocketActor.eventStream()
            guard !Task.isCancelled else { return }
            eventConsumerTask?.cancel()
            eventConsumerTask = Task { [weak self] in
                for await envelope in stream { if Task.isCancelled { return }; self?.handleServerEnvelope(envelope) }
            }
            await webSocketActor.connect(url: serverWSURL, token: token, user: user)
            await updateConnectionState()
            connectionMonitorTask?.cancel()
            connectionMonitorTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.connectionState = await self.webSocketActor.state
                    self.pingLatencyMs = await self.webSocketActor.roundTripMs
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
        }
    }
    public func reconnect(serverWSURL: URL, token: String?, user: UserProfile? = nil) {
        start(serverWSURL: serverWSURL, token: token, user: user)
    }
    public func stop() {
        connectionMonitorTask?.cancel(); connectionMonitorTask = nil
        connectionTask?.cancel(); eventConsumerTask?.cancel(); eventConsumerTask = nil
        connectionTask = Task { await webSocketActor.disconnect() }
        connectionState = .disconnected
    }
    public func reset() {
        stop(); memberProfiles = [:]; Task { await WebRTCManager.shared.hangup() }; rooms = []; activeRoom = nil; messagesByRoomId = [:]; typingUsersByRoomId = [:]; presenceByUserId = [:]
        typingResetTasks.values.forEach { $0.cancel() }; typingResetTasks = [:]
    }
    public func configure(circles: [AccountCircle]) {
        let direct = rooms.filter { !$0.isGroup }
        rooms = circles.map { circle in
            ChatRoom(id: circle.roomId, name: circle.name, isGroup: true, participantIds: circle.memberIds,
                     lastMessage: messagesByRoomId[circle.roomId]?.last)
        } + direct
    }
    public func refreshRooms() async {
        let auth = AuthSessionManager.shared
        guard let token = auth.currentSession?.token, let base = auth.savedServerURL else { return }
        struct Response: Decodable, Sendable { let rooms: [ChatRoom] }
        do {
            let result = try await AccountHTTPClient.shared.request("api/chats", baseURL: base, token: token, as: Response.self)
            guard auth.currentSession?.token == token else { return }
            rooms = result.rooms.map { incoming in
                var room = incoming
                room.lastMessage = messagesByRoomId[room.id]?.last
                room.updatedAt = room.lastMessage?.timestamp ?? room.updatedAt
                room.unreadCount = rooms.first(where: { $0.id == room.id })?.unreadCount ?? 0
                return room
            }.sorted { $0.updatedAt > $1.updatedAt }
        } catch { if auth.currentSession?.token == token { auth.lastError = error.localizedDescription } }
    }
    public func openDirect(userID: String) async -> ChatRoom? {
        let auth = AuthSessionManager.shared
        guard let token = auth.currentSession?.token, let base = auth.savedServerURL else { return nil }
        struct Body: Encodable { let userId: String }
        struct Response: Decodable, Sendable { let room: ChatRoom }
        do {
            let result = try await AccountHTTPClient.shared.request("api/chats/direct", baseURL: base, token: token,
                body: JSONEncoder().encode(Body(userId: userID)), as: Response.self)
            guard auth.currentSession?.token == token else { return nil }
            var room = result.room; room.lastMessage = messagesByRoomId[room.id]?.last
            room.updatedAt = room.lastMessage?.timestamp ?? room.updatedAt
            if let index = rooms.firstIndex(where: { $0.id == room.id }) { rooms[index] = room } else { rooms.append(room) }
            return room
        } catch { if auth.currentSession?.token == token { auth.lastError = error.localizedDescription }; return nil }
    }

    private func refreshProfiles() async {
        let auth = AuthSessionManager.shared
        guard let token = auth.currentSession?.token, let base = auth.savedServerURL else { return }
        struct Members: Decodable, Sendable { let users: [User] }
        var profiles: [String: User] = [:]
        for circle in auth.circles {
            if let result = try? await AccountHTTPClient.shared.request("api/circles/\(circle.id)/members", baseURL: base, token: token, as: Members.self) {
                for user in result.users { profiles[user.id] = user }
            }
        }
        guard auth.currentSession?.token == token else { return }; memberProfiles = profiles
    }
    private func updateConnectionState() async {
        self.connectionState = await webSocketActor.state
        if case .connected = self.connectionState {
            self.pingLatencyMs = await webSocketActor.roundTripMs
            AppLogger.shared.info(.network, "WebSocket connected successfully (RTT: \(self.pingLatencyMs)ms)")
        }
    }
    
    private func subscribeToWebSocketEvents() {
        eventConsumerTask?.cancel()
        eventConsumerTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = await self.webSocketActor.eventStream()
            
            for await envelope in stream {
                self.handleServerEnvelope(envelope)
            }
        }
    }
    
    // MARK: - Event Dispatcher
    
    private func handleServerEnvelope(_ envelope: ServerMessageEnvelope) {
        switch envelope.type {
        case .authenticated:
            Task { await refreshRooms(); await refreshProfiles() }
            connectionState = .connected
            AppLogger.shared.info(.network, "Client authenticated by WebSocket server")
            
        case .messageReceived:
            if var message = envelope.message {
                let currentUserId = AuthSessionManager.shared.currentSession?.user.id
                message.isFromCurrentUser = (message.senderId == currentUserId)
                AppLogger.shared.info(.network, "Received message from \(message.senderName)", metadata: ["roomId": message.roomId])
                insertMessage(message)
            }
            
        case .messageStatusUpdated:
            if let msgId = envelope.messageId, let status = envelope.status, let roomId = envelope.roomId {
                updateMessageStatus(messageId: msgId, roomId: roomId, status: status)
            }
            
        case .typingIndicator:
            if let roomId = envelope.roomId, let displayName = envelope.displayName, let isTyping = envelope.isTyping {
                handlePeerTyping(roomId: roomId, userName: displayName, isTyping: isTyping)
            }
            
        case .presenceUpdated:
            if let presence = envelope.presence {
                self.presenceByUserId[presence.userId] = presence
            }
            
        case .roomHistory:
            if let roomId = envelope.roomId, let history = envelope.history {
                let currentUserId = AuthSessionManager.shared.currentSession?.user.id
                let resolved = history.map { msg -> ChatMessage in
                    var m = msg
                    m.isFromCurrentUser = (m.senderId == currentUserId)
                    return m
                }
                self.messagesByRoomId[roomId] = resolved
                if let i = rooms.firstIndex(where: { $0.id == roomId }) {
                    rooms[i].lastMessage = resolved.last
                    if let timestamp = resolved.last?.timestamp { rooms[i].updatedAt = timestamp }
                }
                AppLogger.shared.info(.network, "Loaded room history for \(roomId) (\(history.count) messages)")
            }
            
        case .roomThemeUpdated:
            if let theme = envelope.roomTheme {
                ThemeManager.shared.handleIncomingRoomTheme(theme)
            }
            
        case .pong:
            // Native WebSocket ping timing is sampled by the connection monitor.
            AppLogger.shared.debug(.network, "WebSocket heartbeat pong received (RTT: \(self.pingLatencyMs)ms)")
            
        case .error:
            let reason = envelope.reason ?? "Server rejected the request."
            if reason.lowercased().contains("session") || reason == "Authentication required" {
                AuthSessionManager.shared.discardSession(); reset()
            }
            AppLogger.shared.warn(.network, reason)
        case .accountUpdated:
            Task {
                let auth = AuthSessionManager.shared
                if let url = auth.savedServerURL { _ = await auth.validateSavedSession(serverURL: url); configure(circles: auth.circles) }
                await refreshRooms(); await refreshProfiles(); accountRevision += 1
            }
        case .callSignal:
            if let signal = envelope.callSignal { Task { await WebRTCManager.shared.handleSignalingPayload(signal) } }
        }
    }
    
    // MARK: - Chat Actions
    
    /// Sends a text message to the active room.
    public func sendTextMessage(_ text: String, in room: ChatRoom, currentUserId: String, currentUserName: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let message = ChatMessage(
            roomId: room.id,
            senderId: currentUserId,
            senderName: currentUserName,
            content: trimmed,
            mediaAttachment: nil,
            timestamp: Date(),
            status: .sending,
            isFromCurrentUser: true
        )
        
        insertMessage(message)
        HapticFeedback.rigid()
        
        // Dispatch via WebSocket
        Task {
            let envelope = ClientMessageEnvelope(type: .sendMessage, roomId: room.id, message: message)
            do {
                try await webSocketActor.send(envelope: envelope)
                updateMessageStatus(messageId: message.id, roomId: room.id, status: .sent)
            } catch {
                updateMessageStatus(messageId: message.id, roomId: room.id, status: .failed)
            }
        }
    }
    
    /// Sends an attachment message.
    public func sendMediaMessage(_ attachment: MediaAttachment, in room: ChatRoom, currentUserId: String, currentUserName: String) {
        let message = ChatMessage(
            roomId: room.id,
            senderId: currentUserId,
            senderName: currentUserName,
            content: "",
            mediaAttachment: attachment,
            timestamp: Date(),
            status: .sending,
            isFromCurrentUser: true
        )
        
        insertMessage(message)
        HapticFeedback.rigid()
        
        Task {
            let envelope = ClientMessageEnvelope(type: .sendMessage, roomId: room.id, message: message)
            do {
                try await webSocketActor.send(envelope: envelope)
                updateMessageStatus(messageId: message.id, roomId: room.id, status: .sent)
            } catch {
                updateMessageStatus(messageId: message.id, roomId: room.id, status: .failed)
            }
        }
    }
    
    /// Emits typing status with auto-reset timer.
    public func emitTyping(isTyping: Bool, in room: ChatRoom) {
        Task {
            let envelope = ClientMessageEnvelope(type: .typing, roomId: room.id, isTyping: isTyping)
            try? await webSocketActor.send(envelope: envelope)
        }
    }
    
    // MARK: - State Mutations
    
    public func insertMessage(_ message: ChatMessage) {
        var existing = messagesByRoomId[message.roomId] ?? []
        if let idx = existing.firstIndex(where: { $0.id == message.id }) {
            existing[idx] = message
        } else {
            existing.append(message)
        }
        messagesByRoomId[message.roomId] = existing
        
        // Update room's last message snippet
        if let rIdx = rooms.firstIndex(where: { $0.id == message.roomId }) {
            rooms[rIdx].lastMessage = message
            rooms[rIdx].updatedAt = message.timestamp
        }
    }
    
    private func updateMessageStatus(messageId: String, roomId: String, status: MessageDeliveryStatus) {
        guard var list = messagesByRoomId[roomId], let idx = list.firstIndex(where: { $0.id == messageId }) else { return }
        list[idx].status = status
        messagesByRoomId[roomId] = list
    }
    
    private func handlePeerTyping(roomId: String, userName: String, isTyping: Bool) {
        var typingSet = typingUsersByRoomId[roomId] ?? []
        if isTyping {
            typingSet.insert(userName)
            // Auto expire after 3.5s
            let key = "\(roomId)_\(userName)"
            typingResetTasks[key]?.cancel()
            typingResetTasks[key] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                self?.handlePeerTyping(roomId: roomId, userName: userName, isTyping: false)
            }
        } else {
            typingSet.remove(userName)
        }
        typingUsersByRoomId[roomId] = typingSet
    }
    
    // MARK: - Initial Mock Preview Data
    
    private func populateInitialMockData() {
        let room1 = ChatRoom(
            id: "room_main",
            name: "The Inner Circle ✨",
            isGroup: true,
            participantIds: ["user_me", "user_alex", "user_elena", "user_marcus"],
            lastMessage: nil,
            updatedAt: Date()
        )
        
        let room2 = ChatRoom(
            id: "room_elena",
            name: "Elena Rostova",
            isGroup: false,
            participantIds: ["user_me", "user_elena"],
            lastMessage: nil,
            updatedAt: Date().addingTimeInterval(-3600)
        )
        
        self.rooms = [room1, room2]
        self.activeRoom = room1
        
        // Populate initial conversation
        let initialMessages: [ChatMessage] = [
            ChatMessage(
                id: "msg_1",
                roomId: "room_main",
                senderId: "user_alex",
                senderName: "Alex",
                content: "Welcome to our private space. Look at how fluid this glass blur is! 💎",
                timestamp: Date().addingTimeInterval(-600),
                status: .read,
                isFromCurrentUser: false
            ),
            ChatMessage(
                id: "msg_2",
                roomId: "room_main",
                senderId: "user_elena",
                senderName: "Elena",
                content: "Specular borders and pure physics. No unneeded clutter.",
                timestamp: Date().addingTimeInterval(-300),
                status: .read,
                isFromCurrentUser: false
            ),
            ChatMessage(
                id: "msg_3",
                roomId: "room_main",
                senderId: "user_me",
                senderName: "Me",
                content: "Testing video compression up to 150 MB right on device. Sending now!",
                timestamp: Date().addingTimeInterval(-60),
                status: .delivered,
                isFromCurrentUser: true
            )
        ]
        
        self.messagesByRoomId["room_main"] = initialMessages
        self.presenceByUserId["user_alex"] = UserPresence(userId: "user_alex", displayName: "Alex", isOnline: true)
        self.presenceByUserId["user_elena"] = UserPresence(userId: "user_elena", displayName: "Elena", isOnline: true)
    }
}
