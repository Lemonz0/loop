import SwiftUI

struct ProfileMentionText: View {
    @Environment(\.profileHostID) private var hostID
    @Namespace private var namespace
    @State private var sourceID = UUID()
    let text: String
    let users: [User]
    private var attributed: AttributedString {
        var result = AttributedString(text)
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_])@([A-Za-z0-9_]{3,32})") else { return result }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text), let fullRange = Range(match.range, in: text),
                  let user = users.first(where: { $0.username?.lowercased() == text[range].lowercased() }),
                  let attributedRange = Range(fullRange, in: result) else { continue }
            result[attributedRange].link = URL(string: "loop-profile://user/" + user.id)
        }
        return result
    }
    var body: some View {
        Text(attributed).matchedTransitionSource(id: sourceID, in: namespace)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "loop-profile", let hostID else { return .systemAction }
                ProfilePresentation.shared.open(ProfileRequest(userID: url.lastPathComponent, context: ProfileContext(source: "mention"), hostID: hostID, sourceID: sourceID, namespace: namespace))
                return .handled
            })
    }
}
struct MessageReactionsView: View {
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    @State private var store = AppEnvironment.shared.chatStore
    var body: some View {
        NavigationStack {
            ZStack { AmbientGlowBackground(); ScrollView { GlassEffectContainer(spacing: 14) { VStack(spacing: 14) {
                ForEach(message.reactions ?? [], id: \.userId) { reaction in
                    let user = store.memberProfiles[reaction.userId] ?? User(id: reaction.userId, name: "Member", allowsTrollPosts: true)
                    HStack { CircleAvatar(user: user); Text(user.name).profileEntry(user.id, name: user.name, source: "reaction"); Spacer(); Text(reaction.emoji) }.padding(16).circleSurface()
                }
            }.padding(20) } } }.navigationTitle("Who reacted").toolbar { Button("Done") { dismiss() } }
        }.environment(\.profileContext, ProfileContext(source: "reaction")).profilePresentationHost()
    }
}
#Preview("Message reactions · dark") { MessageReactionsView(message: ChatMessage(roomId: "preview", senderId: "preview", senderName: "Preview", content: "Hello")).circlePreviewTheme(.aurora) }
#Preview("Message reactions · light") { MessageReactionsView(message: ChatMessage(roomId: "preview", senderId: "preview", senderName: "Preview", content: "Hello")).circlePreviewTheme(.daylight) }
