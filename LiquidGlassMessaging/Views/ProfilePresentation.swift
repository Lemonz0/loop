import SwiftUI

struct ProfileRequest: Identifiable {
    let id = UUID()
    let userID: String
    let context: ProfileContext
    let hostID: UUID
    let sourceID: UUID
    let namespace: Namespace.ID
}
@Observable @MainActor
final class ProfilePresentation {
    static let shared = ProfilePresentation()
    var request: ProfileRequest?
    var isDismissing = false
    var destination: ChatRoom?
    var pendingDestination: ChatRoom?
    var pendingCall: (room: ChatRoom, video: Bool)?
    var navigationRevision = 0
    func open(_ request: ProfileRequest) {
        guard self.request == nil, !isDismissing else { return }
        self.request = request
        HapticFeedback.soft()
        AppLogger.shared.info(.general, "profile_open", metadata: ["source": request.context.source])
    }
    func finishedDismissal() {
        isDismissing = false
        if let pendingDestination { self.pendingDestination = nil; destination = pendingDestination; navigationRevision += 1 }
        if let pendingCall {
            self.pendingCall = nil; navigationRevision += 1
            Task { await WebRTCManager.shared.startCall(roomId: pendingCall.room.id, roomName: pendingCall.room.name, isVideo: pendingCall.video) }
        }
    }
    func reset() { request = nil; destination = nil; pendingDestination = nil; pendingCall = nil; isDismissing = false }
}
private struct ProfileHostKey: EnvironmentKey { static let defaultValue: UUID? = nil }
private struct ProfileContextKey: EnvironmentKey { static let defaultValue = ProfileContext() }
extension EnvironmentValues {
    var profileHostID: UUID? { get { self[ProfileHostKey.self] } set { self[ProfileHostKey.self] = newValue } }
    var profileContext: ProfileContext { get { self[ProfileContextKey.self] } set { self[ProfileContextKey.self] = newValue } }
}
extension View {
    func profilePresentationHost(dismissParentOnNavigate: Bool = true) -> some View { modifier(ProfileHostModifier(dismissParentOnNavigate: dismissParentOnNavigate)) }
    func profileEntry(_ userID: String, name: String, source: String? = nil, enabled: Bool = true) -> some View {
        modifier(ProfileEntryModifier(userID: userID, name: name, source: source, enabled: enabled))
    }
}
private struct ProfileHostModifier: ViewModifier {
    let dismissParentOnNavigate: Bool
    @State private var hostID = UUID()
    @State private var presentation = ProfilePresentation.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismissParent
    func body(content: Content) -> some View {
        content.environment(\.profileHostID, hostID)
            .sheet(item: Binding(get: { presentation.request?.hostID == hostID ? presentation.request : nil }, set: {
                if $0 == nil && presentation.request?.hostID == hostID { presentation.isDismissing = true; presentation.request = nil }
            }), onDismiss: { presentation.finishedDismissal() }) { request in
                Group {
                    if reduceMotion { UserProfileSheet(userID: request.userID, context: request.context) }
                    else { UserProfileSheet(userID: request.userID, context: request.context).navigationTransition(.zoom(sourceID: request.sourceID, in: request.namespace)) }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(40)
            }
            .onChange(of: presentation.navigationRevision) { _, _ in if dismissParentOnNavigate { dismissParent() } }
    }
}
private struct ProfileEntryModifier: ViewModifier {
    @Environment(\.profileHostID) private var hostID
    @Environment(\.profileContext) private var context
    @Namespace private var namespace
    @State private var sourceID = UUID()
    let userID: String
    let name: String
    let source: String?
    let enabled: Bool
    private var resolvedContext: ProfileContext {
        if let source { return ProfileContext(source: source) }
        return context
    }
    func body(content: Content) -> some View {
        if enabled {
            content.contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44)
                .matchedTransitionSource(id: sourceID, in: namespace)
                .highPriorityGesture(TapGesture().onEnded { open() })
                .contextMenu { Button("Open profile", systemImage: "person.crop.circle") { open() } } preview: {
                    ProfilePeek(userID: userID, name: name, context: resolvedContext)
                }
                .accessibilityHidden(false).accessibilityElement(children: .ignore)
                .accessibilityLabel("Profile of \(name)").accessibilityAddTraits(.isButton)
                .accessibilityAction { open() }
        } else { content }
    }
    private func open() {
        guard let hostID else { return }
        ProfilePresentation.shared.open(ProfileRequest(userID: userID, context: resolvedContext, hostID: hostID, sourceID: sourceID, namespace: namespace))
    }
}
private struct ProfilePeek: View {
    let userID: String
    let name: String
    let context: ProfileContext
    @State private var card: PersonCard?
    var body: some View {
        VStack(spacing: 14) {
            CircleAvatar(user: card?.avatarUser ?? User(id: userID, name: name, allowsTrollPosts: true), size: 80, opensProfile: false)
            Text(card?.user.displayName ?? name).font(.title2.bold()).lineLimit(2)
            if let card {
                if card.state == "active" { Text("@" + card.user.username); Text(card.bio ?? "").lineLimit(3) }
                else { Text(card.state == "blocked" ? "Blocked" : card.state == "private" ? "Private profile" : "Deleted account") }
            } else { Text("Loading profile").redacted(reason: .placeholder) }
        }.padding(24).frame(width: 300).circleSurface()
            .task { card = ProfileRepository.shared.cached(userID, context: context); card = try? await ProfileRepository.shared.load(userID, context: context) }
    }
}
