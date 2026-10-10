import Foundation

struct ProfileContext: Sendable {
    var source: String = "profile"
    var roomID: String?
    var circleID: String?
}
struct ProfilePersonal: Codable, Sendable {
    var nickname = ""
    var note = ""
    var contact = false
    var blocked = false
    var muted = false
    var requested = false
    var clearBefore: Date?
    var disappearingSeconds = 0
}
struct ProfileGroup: Codable, Sendable {
    let circleId: String
    let name: String
    let role: String
    let joinedAt: String?
    let addedBy: String?
    let restricted: Bool
    let canManage: Bool
}
struct MutualGroup: Identifiable, Codable, Sendable { let id: String; let name: String }
struct PersonCard: Codable, Sendable {
    let user: UserProfile
    let isSelf: Bool
    let state: String
    let kind: String
    let verified: Bool
    var personal: ProfilePersonal
    let bio: String?
    let pronouns: String?
    let customStatus: String?
    let timeZone: String?
    let memberSince: Date?
    let presenceVisible: Bool
    let presence: UserPresence?
    let mutualGroups: [MutualGroup]
    let mutualContacts: [User]
    let links: [String]
    let group: ProfileGroup?
    let canCall: Bool
    let canMessage: Bool
    let sharedItems: [ChatMessage]?
    var avatarUser: User { User(id: user.id, name: user.displayName, avatarURL: user.avatarURL, allowsTrollPosts: true) }
}
struct ProfileSettings: Codable, Sendable {
    var bio = ""
    var pronouns = ""
    var status = ""
    var timeZone = ""
    var `private` = false
    var showLocalTime = false
    var presence = "everyone"
    var links: [String] = []
}
struct ProfileAction: Encodable, Sendable {
    let action: String
    var value: Bool?
    var note: String?
    var nickname: String?
    var seconds: Int?
    var reason: String?
}
struct LoopCallRecord: Identifiable, Decodable, Sendable {
    let id: String
    let roomId: String
    let callerId: String
    let date: Date
    let isVideo: Bool
    let users: [User]
}
