import Foundation

/// Authenticated user profile within the closed circle.
public struct UserProfile: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var username: String
    public var displayName: String
    public var avatarURL: URL?
    public var bio: String?
    
    public init(
        id: String,
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        bio: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bio = bio
    }
}

/// Session token container returned after secret key verification.
public struct AuthSession: Codable, Sendable {
    public let token: String
    public var user: UserProfile
    public let issuedAt: Date
    public let expiresAt: Date
    
    public init(
        token: String,
        user: UserProfile,
        issuedAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(30 * 86400) // 30 days
    ) {
        self.token = token
        self.user = user
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }
}

/// Closed circle auth validation request/response payloads.
public struct InviteAuthRequest: Codable, Sendable {
    public let secretKey: String
    public let chosenDisplayName: String
    public let username: String
    public let password: String
    
    public init(secretKey: String, chosenDisplayName: String, username: String, password: String) {
        self.secretKey = secretKey
        self.chosenDisplayName = chosenDisplayName
        self.username = username
        self.password = password
    }
}

public struct InviteAuthResponse: Codable, Sendable {
    public let success: Bool
    public let session: AuthSession?
    public let errorMessage: String?
}

public struct AccountCircle: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let ownerId: String?
    public let memberIds: [String]
    public let roomId: String
}
public struct AccountProfileResponse: Codable, Sendable {
    public let user: UserProfile
    public let circles: [AccountCircle]
}
public struct AccountLoginRequest: Codable, Sendable {
    public let username: String
    public let password: String
}
public struct AccountInvite: Codable, Sendable {
    public let code: String
    public let circleId: String
    public let expiresAt: Date
}
public struct StoredAccountSession: Codable, Sendable {
    public var session: AuthSession
    public let serverURL: URL
}
public enum AccountCodec {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid server date")
        }
        return decoder
    }
    public static func serverURL(_ value: String) -> URL? {
        guard var parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        if scheme == "http" {
            let components = host.split(separator: ".")
            let octets = components.compactMap { Int($0) }
            let localIP = components.count == 4 && octets.count == 4 && octets.allSatisfy { (0...255).contains($0) } &&
                (octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])))
            guard localIP || host == "localhost" || host.hasSuffix(".local") else { return nil }
        }
        parts.scheme = scheme; parts.host = host
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !parts.path.isEmpty { parts.path = "/" + parts.path }
        return parts.url
    }
    public static func valid(_ stored: StoredAccountSession, at date: Date = Date()) -> Bool {
        stored.session.expiresAt > date && stored.session.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
    }
}
