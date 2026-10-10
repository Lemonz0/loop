import Foundation

// MARK: - Call Signaling Payloads

public enum CallSignalType: String, Codable, Sendable {
    case offer
    case answer
    case iceCandidate = "ice_candidate"
    case hangup
    case ping
}

public struct CallSignalPayload: Codable, Sendable {
    public let callId: String
    public let roomId: String
    public let senderId: String
    public let targetId: String? // nil for broadcast to room
    public let signalType: CallSignalType
    public let sdp: String?
    public let sdpMid: String?
    public let sdpMLineIndex: Int32?
    public let candidate: String?
    public let isVideo: Bool
    
    public init(
        callId: String,
        roomId: String,
        senderId: String,
        targetId: String? = nil,
        signalType: CallSignalType,
        sdp: String? = nil,
        sdpMid: String? = nil,
        sdpMLineIndex: Int32? = nil,
        candidate: String? = nil,
        isVideo: Bool = false
    ) {
        self.callId = callId
        self.roomId = roomId
        self.senderId = senderId
        self.targetId = targetId
        self.signalType = signalType
        self.sdp = sdp
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
        self.candidate = candidate
        self.isVideo = isVideo
    }
}

// MARK: - Room Theme

public struct RoomTheme: Codable, Sendable, Equatable {
    public let roomId: String
    public let themeType: String // "preset" or "custom"
    public let presetName: String? // "onyx", "slate", "frost"
    public let wallpaperUrl: String?
    public let updatedBy: String?
    public let updatedAt: String?
    
    public init(
        roomId: String,
        themeType: String,
        presetName: String? = nil,
        wallpaperUrl: String? = nil,
        updatedBy: String? = nil,
        updatedAt: String? = nil
    ) {
        self.roomId = roomId
        self.themeType = themeType
        self.presetName = presetName
        self.wallpaperUrl = wallpaperUrl
        self.updatedBy = updatedBy
        self.updatedAt = updatedAt
    }
}

// MARK: - WebSocket Wire Envelope

public enum ClientEventType: String, Codable, Sendable {
    case auth
    case joinRoom = "join_room"
    case leaveRoom = "leave_room"
    case sendMessage = "send_message"
    case typing
    case callSignal = "call_signal"
    case updateRoomTheme = "update_room_theme"
    case ping
}

public struct ClientMessageEnvelope: Codable, Sendable {
    public let type: ClientEventType
    public let token: String?
    public let user: UserProfile?
    public let roomId: String?
    public let message: ChatMessage?
    public let isTyping: Bool?
    public let callSignal: CallSignalPayload?
    public let roomTheme: RoomTheme?
    
    public init(
        type: ClientEventType,
        token: String? = nil,
        user: UserProfile? = nil,
        roomId: String? = nil,
        message: ChatMessage? = nil,
        isTyping: Bool? = nil,
        callSignal: CallSignalPayload? = nil,
        roomTheme: RoomTheme? = nil
    ) {
        self.type = type
        self.token = token
        self.user = user
        self.roomId = roomId
        self.message = message
        self.isTyping = isTyping
        self.callSignal = callSignal
        self.roomTheme = roomTheme
    }
}

public enum ServerEventType: String, Codable, Sendable {
    case authenticated
    case accountUpdated = "account_updated"
    case messageReceived = "message_received"
    case messageStatusUpdated = "message_status_updated"
    case typingIndicator = "typing_indicator"
    case presenceUpdated = "presence_updated"
    case callSignal = "call_signal"
    case roomHistory = "room_history"
    case roomThemeUpdated = "room_theme_updated"
    case pong
    case error
}

public struct ServerMessageEnvelope: Codable, Sendable {
    public let type: ServerEventType
    public let user: UserProfile?
    public let roomId: String?
    public let message: ChatMessage?
    public let messageId: String?
    public let status: MessageDeliveryStatus?
    public let userId: String?
    public let displayName: String?
    public let isTyping: Bool?
    public let presence: UserPresence?
    public let callSignal: CallSignalPayload?
    public let history: [ChatMessage]?
    public let roomTheme: RoomTheme?
    public let reason: String?
}
