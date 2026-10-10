import Foundation

public struct User: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var avatarURL: URL?
    public var allowsTrollPosts: Bool
}

public struct CircleMedia: Codable, Hashable, Sendable {
    public var url: URL?
    public var imageData: Data?
    public init(url: URL? = nil, imageData: Data? = nil) {
        self.url = url; self.imageData = imageData
    }
}

public struct Post: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var author: User
    public var media: [CircleMedia]
    public var caption: String
    public var createdAt: Date
    public var likes: Int
    public var comments: [String]
    public var isLiked: Bool
}

public struct Story: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var user: User
    public var media: CircleMedia
    public var caption: String
    public var createdAt: Date
    public var expiresAt: Date
    public var isSeen: Bool
    public var isLiked: Bool
    public func isActive(at date: Date) -> Bool { expiresAt > date }
}

/// Public payload deliberately contains no authorship or uploader identity.
public struct TrollPost: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var imageURL: URL?
    public var imageData: Data?
    public var caption: String
    public var createdAt: Date
    public var reactions: Int
    public var hasReacted: Bool
    public var aspectRatio: Double
}

public struct CircleSnapshot: Codable, Sendable {
    public var friends: [User]
    public var posts: [Post]
    public var stories: [Story]
    public var trollPosts: [TrollPost]
}

public enum CircleRepositoryError: LocalizedError {
    case optedOut, missingSubjects, emptyMedia, expiredStory, notFound
    public var errorDescription: String? {
        switch self {
        case .optedOut: return "Someone in this photo does not allow Troll Wall posts."
        case .missingSubjects: return "Select everyone shown in this photo."
        case .emptyMedia: return "Choose a photo first."
        case .expiredStory: return "This story has expired."
        case .notFound: return "This item is no longer available."
        }
    }
}

public struct PrivateStoryReply: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sender: User
    public let text: String
    public let createdAt: Date
}
public struct TrollModerationReport: Identifiable, Codable, Sendable {
    public let id: UUID
    public let trollId: UUID
    public let reason: String
    public let createdAt: Date
}
