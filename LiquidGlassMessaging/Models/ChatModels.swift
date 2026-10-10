import Foundation

// MARK: - Media Models

public enum MediaType: String, Codable, Sendable {
    case image
    case video
    case audio
    case document
}

public struct MediaAttachment: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let fileName: String
    public let mimeType: String
    public let byteSize: Int64
    public var localURL: URL?
    public var remoteURL: URL?
    public var thumbnailURL: URL?
    public var width: Double?
    public var height: Double?
    public var durationSeconds: Double?
    public let mediaType: MediaType
    
    public init(
        id: String = UUID().uuidString,
        fileName: String,
        mimeType: String,
        byteSize: Int64,
        localURL: URL? = nil,
        remoteURL: URL? = nil,
        thumbnailURL: URL? = nil,
        width: Double? = nil,
        height: Double? = nil,
        durationSeconds: Double? = nil,
        mediaType: MediaType
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.localURL = localURL
        self.remoteURL = remoteURL
        self.thumbnailURL = thumbnailURL
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
        self.mediaType = mediaType
    }
    
    /// Human readable file size representation (e.g. "14.2 MB")
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

// MARK: - Message Status & Model

public enum MessageDeliveryStatus: String, Codable, Sendable {
    case sending
    case sent
    case delivered
    case read
    case failed
}

public struct ChatMessage: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let roomId: String
    public let senderId: String
    public let senderName: String
    public var senderAvatarURL: URL?
    public var content: String
    public var mediaAttachment: MediaAttachment?
    public let timestamp: Date
    public var status: MessageDeliveryStatus
    public var isFromCurrentUser: Bool
    private enum CodingKeys: String, CodingKey {
        case id, roomId, senderId, senderName, senderAvatarURL, content, mediaAttachment, timestamp, status, isFromCurrentUser
    }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        roomId = try fields.decode(String.self, forKey: .roomId)
        senderId = try fields.decode(String.self, forKey: .senderId)
        senderName = try fields.decode(String.self, forKey: .senderName)
        senderAvatarURL = try fields.decodeIfPresent(URL.self, forKey: .senderAvatarURL)
        content = try fields.decode(String.self, forKey: .content)
        mediaAttachment = try fields.decodeIfPresent(MediaAttachment.self, forKey: .mediaAttachment)
        timestamp = try fields.decode(Date.self, forKey: .timestamp)
        status = try fields.decode(MessageDeliveryStatus.self, forKey: .status)
        isFromCurrentUser = try fields.decodeIfPresent(Bool.self, forKey: .isFromCurrentUser) ?? false
    }

    
    public init(
        id: String = UUID().uuidString,
        roomId: String,
        senderId: String,
        senderName: String,
        senderAvatarURL: URL? = nil,
        content: String,
        mediaAttachment: MediaAttachment? = nil,
        timestamp: Date = Date(),
        status: MessageDeliveryStatus = .sent,
        isFromCurrentUser: Bool = false
    ) {
        self.id = id
        self.roomId = roomId
        self.senderId = senderId
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.content = content
        self.mediaAttachment = mediaAttachment
        self.timestamp = timestamp
        self.status = status
        self.isFromCurrentUser = isFromCurrentUser
    }
}

// MARK: - User Presence

public struct UserPresence: Identifiable, Codable, Sendable, Hashable {
    public var id: String { userId }
    public let userId: String
    public let displayName: String
    public var isOnline: Bool
    public var lastSeen: Date
    public var isTypingInRoomId: String?
    
    public init(
        userId: String,
        displayName: String,
        isOnline: Bool = false,
        lastSeen: Date = Date(),
        isTypingInRoomId: String? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.isTypingInRoomId = isTypingInRoomId
    }
}

// MARK: - Chat Room

public struct ChatRoom: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var isGroup: Bool
    public var avatarURL: URL?
    public var participantIds: [String]
    public var lastMessage: ChatMessage?
    public var unreadCount: Int
    public var updatedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        isGroup: Bool,
        avatarURL: URL? = nil,
        participantIds: [String] = [],
        lastMessage: ChatMessage? = nil,
        unreadCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isGroup = isGroup
        self.avatarURL = avatarURL
        self.participantIds = participantIds
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
    }
}
