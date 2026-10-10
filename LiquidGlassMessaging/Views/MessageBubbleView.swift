import SwiftUI

/// Glossy message bubble with liquid glass accents, specular borders, and fluid inline media.
public struct MessageBubbleView: View {
    @Environment(\.appTheme) private var theme
    public let message: ChatMessage
    public let isGroup: Bool
    @State private var showsReactions = false
    @State private var store = AppEnvironment.shared.chatStore

    public init(message: ChatMessage, isGroup: Bool = false) {
        self.message = message
        self.isGroup = isGroup
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromCurrentUser {
                Spacer(minLength: 44)
            } else {
                CircleAvatar(user: store.memberProfiles[message.senderId] ?? User(id: message.senderId, name: message.senderName,
                    avatarURL: message.senderAvatarURL, allowsTrollPosts: true), size: 30)

            }

            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender Name Header in Group Chat
                if isGroup && !message.isFromCurrentUser {
                    Text(store.memberProfiles[message.senderId]?.name ?? message.senderName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.accent)
                        .padding(.leading, 4)
                        .profileEntry(message.senderId, name: message.senderName)
                }

                // Bubble Container
                VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 6) {
                    if let replyID = message.replyToId, let original = store.messagesByRoomId[message.roomId]?.first(where: { $0.id == replyID }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(original.senderName).font(.caption.bold()).profileEntry(original.senderId, name: original.senderName, source: "reply")
                            Text(original.content.isEmpty ? "Attachment" : original.content).font(.caption).lineLimit(2).foregroundStyle(theme.secondaryText)
                        }.padding(10).circleSurface(radius: 14)
                    }
                    // Inline Media Card (if attached)
                    if let attachment = message.mediaAttachment {
                        InlineMediaView(attachment: attachment)
                    }

                    // Message Text
                    if !message.content.isEmpty {
                        ProfileMentionText(text: message.content, users: Array(store.memberProfiles.values))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Footer: Timestamp and Delivery Ticks
                    HStack(spacing: 4) {
                        Text(formatTimestamp(message.timestamp))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)

                        if message.isFromCurrentUser {
                            statusIndicator(message.status)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .liquidGlassBubble(isFromCurrentUser: message.isFromCurrentUser)
                .contextMenu {
                    Button("Reply", systemImage: "arrowshape.turn.up.left") { store.replyDraft = message }
                    ForEach(["❤️", "👍", "😂", "😮", "😢"], id: \.self) { emoji in Button(emoji) { react(emoji) } }
                    Button("Who reacted", systemImage: "face.smiling") { showsReactions = true }
                }
                if let reactions = message.reactions, !reactions.isEmpty {
                    Button { showsReactions = true } label: { Text(reactions.map(\.emoji).joined() + " \(reactions.count)").font(.caption).frame(minHeight: 44) }.buttonStyle(.glass)
                }
            }

            if !message.isFromCurrentUser {
                Spacer(minLength: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .sheet(isPresented: $showsReactions) { MessageReactionsView(message: message) }
    }

    private func react(_ emoji: String) {
        struct Body: Encodable { let emoji: String }
        struct Result: Decodable, Sendable { let success: Bool }
        Task { do { let _: Result = try await ProfileRepository.shared.request("api/chats/\(message.roomId)/messages/\(message.id)/reaction", body: JSONEncoder().encode(Body(emoji: emoji))) } catch { AuthSessionManager.shared.lastError = error.localizedDescription } }
    }
    // MARK: - Status Indicators

    @ViewBuilder
    private func statusIndicator(_ status: MessageDeliveryStatus) -> some View {
        switch status {
        case .sending:
            ProgressView()
                .scaleEffect(0.6)
                .tint(.primary)
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
        case .delivered:
            Image(systemName: "checkmark.seal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
        case .read:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.accent)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.destructive)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func formatTimestamp(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
