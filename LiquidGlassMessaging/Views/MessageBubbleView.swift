import SwiftUI

/// Glossy message bubble with liquid glass accents, specular borders, and fluid inline media.
public struct MessageBubbleView: View {
    @Environment(\.appTheme) private var theme
    public let message: ChatMessage
    public let isGroup: Bool
    @State private var store = AppEnvironment.shared.chatStore

    public init(message: ChatMessage, isGroup: Bool = false) {
        self.message = message
        self.isGroup = isGroup
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromCurrentUser {
                Spacer(minLength: 44)
            } else if isGroup {
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
                }

                // Bubble Container
                VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 6) {
                    // Inline Media Card (if attached)
                    if let attachment = message.mediaAttachment {
                        InlineMediaView(attachment: attachment)
                    }

                    // Message Text
                    if !message.content.isEmpty {
                        Text(message.content)
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
            }

            if !message.isFromCurrentUser {
                Spacer(minLength: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
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
