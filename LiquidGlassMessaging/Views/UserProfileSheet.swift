import SwiftUI
import UIKit

/// The same card is used by every identity entry point. All permissions come from the server.
struct UserProfileSheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let userID: String
    let context: ProfileContext
    private let isPreview: Bool
    @State private var card: PersonCard?
    @State private var error: String?
    @State private var busy = false
    @State private var nickname = ""
    @State private var note = ""
    @State private var expandedBio = false
    @State private var showAvatar = false
    @State private var showMedia = false
    @State private var showEdit = false
    @State private var confirmation: String?
    @State private var reportReason = ""
    @State private var showReport = false
    @State private var store = AppEnvironment.shared.chatStore
    init(userID: String, context: ProfileContext = ProfileContext(), preview: PersonCard? = nil) {
        self.userID = userID; self.context = context
        isPreview = preview != nil
        _card = State(initialValue: preview ?? ProfileRepository.shared.cached(userID, context: context))
        _nickname = State(initialValue: (preview ?? ProfileRepository.shared.cached(userID, context: context))?.personal.nickname ?? "")
        _note = State(initialValue: (preview ?? ProfileRepository.shared.cached(userID, context: context))?.personal.note ?? "")
    }
    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 14) {
                    if let card {
                        header(card)
                        if card.state != "deleted" { actions(card) }
                        if card.state == "active" {
                            if let group = card.group { groupSection(group) }
                            about(card)
                            mutual(card)
                            if !card.isSelf {
                                sharedMedia
                                if context.roomID != nil && context.circleID == nil { chatSettings(card) }
                                privateNote
                            }
                            if !card.links.isEmpty { links(card) }
                        }
                    } else { skeleton }
                    if let error {
                        section("Connection") {
                            Text(card == nil ? error : "Showing cached profile. " + error).foregroundStyle(theme.secondaryText)
                            Button("Retry", systemImage: "arrow.clockwise") { Task { await refresh() } }.buttonStyle(.glass)
                        }
                    }
                    Button("Close", systemImage: "xmark") { dismiss() }.buttonStyle(.glass).frame(minHeight: 44)
                }.padding(20)
            }
        }
        // Keep the native sheet's adaptive glass. A decorative ambient layer must not cover it.
        .background { AmbientGlowBackground().opacity(0.08).allowsHitTesting(false) }
        .background { ProfileBackdropDismiss().frame(width: 0, height: 0).allowsHitTesting(false) }
        .task { if !isPreview { await refresh() } }
        .onChange(of: store.accountRevision) { _, _ in if !isPreview { Task { await refresh() } } }
        .fullScreenCover(isPresented: $showAvatar) { if let card { ProfileAvatarViewer(user: card.avatarUser) } }
        .sheet(isPresented: $showMedia) { ProfileSharedMediaView(messages: sharedMessages) }
        .sheet(isPresented: $showEdit, onDismiss: { Task { await refresh() } }) { ProfileEditorView() }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            Button("Confirm", role: .destructive) {
                if let action = confirmation { confirmation = nil; if action == "remove" { manage(action) } else { perform(ProfileAction(action: action, value: action == "block" ? true : nil)) } }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        }
        .alert("Report account", isPresented: $showReport) {
            TextField("Reason", text: $reportReason)
            Button("Send report") { perform(ProfileAction(action: "report", reason: reportReason)) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your report is stored privately for moderation.") }
    }
    private var confirmationTitle: String {
        switch confirmation { case "remove": return "Remove this member from the group?"; case "clear": return "Clear this chat for you?"; default: return "Block this account?" }
    }
    private func header(_ card: PersonCard) -> some View {
        let groupLayout = card.group != nil && !typeSize.isAccessibilitySize
        let layout = groupLayout ? AnyLayout(HStackLayout(alignment: .center, spacing: 16)) : AnyLayout(VStackLayout(spacing: 12))
        return VStack(spacing: 12) {
            HStack { Spacer(); if !card.isSelf && card.state == "active" { more(card) } }
            layout {
                Button { track("avatar"); showAvatar = true } label: { CircleAvatar(user: card.avatarUser, size: groupLayout ? 88 : 104, opensProfile: false, generic: card.state == "deleted") }
                    .buttonStyle(.plain).accessibilityLabel("View profile photo full screen").disabled(card.state == "deleted")
                VStack(alignment: groupLayout ? .leading : .center, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(card.user.displayName).font(.title.bold()).lineLimit(2).multilineTextAlignment(groupLayout ? .leading : .center)
                        if card.verified { Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.accent).accessibilityLabel("Verified") }
                    }.contentShape(Rectangle()).onTapGesture { if card.state == "active" { track("copy_name"); UIPasteboard.general.string = card.user.displayName; HapticFeedback.soft() } }.accessibilityHint("Copy display name")
                    if card.state == "active" {
                        Button("@" + card.user.username) { track("copy_username"); UIPasteboard.general.string = "@" + card.user.username; HapticFeedback.soft() }
                            .buttonStyle(.plain).foregroundStyle(theme.secondaryText).frame(minHeight: 44).accessibilityHint("Copy username")
                        if card.kind != "person" { Label(card.kind == "bot" ? "Bot" : "Official account", systemImage: card.kind == "bot" ? "cpu" : "checkmark.seal").font(.subheadline).padding(8).circleSurface(radius: 16) }
                        if let group = card.group { Text(group.role).font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 8).glassEffect(.regular.tint(theme.glassTint), in: Capsule()) }
                        if card.presenceVisible { Text(presenceLabel(card)).font(.subheadline.weight(.semibold)).foregroundStyle(theme.secondaryText) }
                        if let status = card.customStatus, !status.isEmpty { Text(status).font(.subheadline).lineLimit(2).padding(12).circleSurface(radius: 20) }
                    } else if card.state == "blocked" { Label("Blocked account", systemImage: "hand.raised.fill").foregroundStyle(theme.secondaryText) }
                    else if card.state == "private" { Label("Private profile", systemImage: "lock.fill").foregroundStyle(theme.secondaryText) }
                }
            }
        }.frame(maxWidth: .infinity)
    }
    private func track(_ action: String) { AppLogger.shared.info(.general, "profile_action", metadata: ["source": context.source, "action": action]) }
    @ViewBuilder private func actions(_ card: PersonCard) -> some View {
        if card.isSelf { Button("Edit profile", systemImage: "pencil") { track("edit"); showEdit = true }.buttonStyle(.glassProminent).frame(minHeight: 44) }
        else if card.state == "blocked" {
            if card.personal.blocked { Button("Unblock", systemImage: "hand.raised.slash") { perform(ProfileAction(action: "block", value: false)) }.buttonStyle(.glassProminent).disabled(busy) }
        }
        else if card.state == "private" { Button(card.personal.requested ? "Contact requested" : "Request contact", systemImage: "person.badge.plus") { perform(ProfileAction(action: "request")) }.buttonStyle(.glassProminent).disabled(busy || card.personal.requested) }
        else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 10) {
                if card.canMessage {
                    Button { openChat(video: nil) } label: { actionLabel(context.roomID != nil && context.circleID == nil ? "Go to chat" : "Message", "bubble.left") }
                        .buttonStyle(.glassProminent).tint(theme.accent)
                }
                if card.canCall {
                    Button { openChat(video: false) } label: { actionLabel("Call", "phone") }.buttonStyle(.glass)
                    Button { openChat(video: true) } label: { actionLabel("Video", "video") }.buttonStyle(.glass)
                }
                Button { perform(ProfileAction(action: "mute", value: !card.personal.muted)) } label: { actionLabel(card.personal.muted ? "Unmute" : "Mute", card.personal.muted ? "bell" : "bell.slash") }.buttonStyle(.glass)
            }.disabled(busy)
        }
    }
    private func actionLabel(_ text: String, _ symbol: String) -> some View {
        VStack(spacing: 8) { Image(systemName: symbol).font(.title3); Text(text).font(.caption.weight(.semibold)).lineLimit(2) }.frame(maxWidth: .infinity, minHeight: 64)
    }
    private func more(_ card: PersonCard) -> some View {
        Menu {
            ShareLink(item: "\(card.user.displayName) — @\(card.user.username)", label: { Label("Share contact", systemImage: "square.and.arrow.up") })
            Button(card.personal.contact ? "Remove contact" : "Add contact", systemImage: "person.badge.plus") { perform(ProfileAction(action: "contact", value: !card.personal.contact)) }
            Button("Block", systemImage: "hand.raised", role: .destructive) { confirmation = "block" }
            Button("Report", systemImage: "flag", role: .destructive) { showReport = true }
            if context.roomID != nil && context.circleID == nil { Button("Clear chat", systemImage: "trash", role: .destructive) { confirmation = "clear" } }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("More profile actions")
    }
    private func about(_ card: PersonCard) -> some View {
        section("About") {
            if let bio = card.bio, !bio.isEmpty {
                Text(bio).lineLimit(expandedBio ? nil : 5).textSelection(.enabled)
                if bio.count > 200 { Button(expandedBio ? "Show less" : "Read more") { expandedBio.toggle() }.buttonStyle(.glass) }
            } else { Text("No bio added").foregroundStyle(theme.secondaryText) }
            if let pronouns = card.pronouns, !pronouns.isEmpty { row("Pronouns", pronouns) }
            if let zone = card.timeZone, let timeZone = TimeZone(identifier: zone) {
                TimelineView(.periodic(from: .now, by: 60)) { clock in row("Local time", localTime(clock.date, zone: timeZone)) }
            }
            if let date = card.memberSince { row("Member since", date.formatted(.dateTime.month(.wide).year())) }
        }
    }
    private func mutual(_ card: PersonCard) -> some View {
        section("In common") {
            row("Mutual groups", "\(card.mutualGroups.count)")
            ForEach(card.mutualGroups.prefix(3)) { Text($0.name).font(.subheadline).foregroundStyle(theme.secondaryText) }
            row("Mutual contacts", "\(card.mutualContacts.count)")
            HStack(spacing: -6) { ForEach(card.mutualContacts.prefix(4)) { CircleAvatar(user: $0, size: 32, opensProfile: false) } }.accessibilityLabel(card.mutualContacts.prefix(4).map(\.name).joined(separator: ", "))
        }
    }
    private func groupSection(_ group: ProfileGroup) -> some View {
        VStack(spacing: 14) {
            section("In " + group.name) {
                row("Role", group.role)
                if let date = group.joinedAt, let parsed = ISO8601DateFormatter.profileDate(date) { row("Joined group", parsed.formatted(date: .abbreviated, time: .omitted)) }
                if let addedBy = group.addedBy { row("Added by", addedBy) }
                if group.restricted { Label("Restricted permissions", systemImage: "lock") }
            }
            if group.canManage {
                section("Admin actions") {
                    Button(group.role == "Admin" ? "Change role to Member" : "Change role to Admin") { manage(group.role == "Admin" ? "demote" : "promote") }.buttonStyle(.glass)
                    Button(group.restricted ? "Restore permissions" : "Restrict permissions") { manage(group.restricted ? "unrestrict" : "restrict") }.buttonStyle(.glass)
                    Button("Remove from group", role: .destructive) { confirmation = "remove" }.buttonStyle(.glass)
                }.disabled(busy)
            }
        }
    }
    private var sharedMessages: [ChatMessage] {
        card?.sharedItems ?? []
    }
    private var sharedMedia: some View {
        section("Shared media, links & files") {
            if sharedMessages.isEmpty { Text("No shared items yet").foregroundStyle(theme.secondaryText) }
            else {
                HStack(spacing: 10) {
                    ForEach(sharedMessages.prefix(3)) { message in
                        Image(systemName: message.mediaAttachment?.mediaType == .image ? "photo" : message.mediaAttachment?.mediaType == .video ? "video" : message.mediaAttachment == nil ? "link" : "doc")
                            .frame(maxWidth: .infinity, minHeight: 64).circleSurface(radius: 16)
                    }
                }
                Button("See all (\(sharedMessages.count))") { track("shared_media"); showMedia = true }.buttonStyle(.glass)
            }
        }
    }
    private func chatSettings(_ card: PersonCard) -> some View {
        section("Chat settings") {
            Toggle("Mute conversation", isOn: Binding(get: { card.personal.muted }, set: { perform(ProfileAction(action: "mute", value: $0)) }))
            Picker("Disappearing messages", selection: Binding(get: { card.personal.disappearingSeconds }, set: { perform(ProfileAction(action: "disappearing", seconds: $0)) })) {
                Text("Off").tag(0); Text("24 hours").tag(86400); Text("7 days").tag(604800)
            }
            Text("Messages expire using the shorter duration chosen by either participant.").font(.caption).foregroundStyle(theme.secondaryText)
        }.disabled(busy)
    }
    private var privateNote: some View {
        section("Only you can see this") {
            TextField("Private nickname", text: $nickname).textContentType(.nickname).onSubmit { saveNote() }
            TextField("Private note", text: $note, axis: .vertical).lineLimit(3...8)
            Button("Save private note") { saveNote() }.buttonStyle(.glass).disabled(busy || nickname.count > 80 || note.count > 4000)
        }
    }
    private func links(_ card: PersonCard) -> some View {
        section("Links") { ForEach(card.links, id: \.self) { value in if let url = URL(string: value), url.scheme == "https" { Link(value, destination: url).lineLimit(1).frame(minHeight: 44) } } }
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(title).foregroundStyle(theme.secondaryText); Spacer(minLength: 12); Text(value).multilineTextAlignment(.trailing) }.font(.subheadline)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(theme.secondaryText); content() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20).circleSurface(radius: 28)
    }
    private var skeleton: some View {
        VStack(spacing: 14) { Image(systemName: "person.crop.circle.fill").font(.system(size: 90)); Text("Display name").font(.title.bold()); Text("@username"); section("About") { Text("Profile details are loading. More information will appear here.") } }
            .redacted(reason: .placeholder).accessibilityLabel("Loading profile")
    }
    private func localTime(_ date: Date, zone: TimeZone) -> String { let formatter = DateFormatter(); formatter.timeStyle = .short; formatter.timeZone = zone; return formatter.string(from: date) }
    private func presenceLabel(_ card: PersonCard) -> String {
        guard let presence = card.presence else { return "Recently" }
        if presence.isOnline { return "Online" }
        if presence.lastSeen.timeIntervalSince1970 <= 0 { return "Recently" }
        return "Last seen " + presence.lastSeen.formatted(.relative(presentation: .named))
    }
    private func refresh() async {
        do {
            let refreshed = try await ProfileRepository.shared.load(userID, context: context)
            if card == nil || nickname == card?.personal.nickname { nickname = refreshed.personal.nickname }
            if card == nil || note == card?.personal.note { note = refreshed.personal.note }
            card = refreshed; error = nil
        }
        catch { if !AccountHTTPClient.isCancellation(error) { self.error = error.localizedDescription; if let http = error as? AccountHTTPError, [401, 403, 404].contains(http.status) { card = nil } } }
    }
    private func saveNote() { perform(ProfileAction(action: "note", note: note, nickname: nickname)) }
    private func perform(_ action: ProfileAction) {
        guard !busy else { return }; busy = true
        AppLogger.shared.info(.general, "profile_action", metadata: ["source": context.source, "action": action.action])
        Task { defer { busy = false }; do { card = try await ProfileRepository.shared.perform(userID, action: action, context: context); error = nil; HapticFeedback.success() } catch { self.error = error.localizedDescription } }
    }
    private func manage(_ action: String) {
        guard let group = card?.group, !busy else { return }; busy = true
        AppLogger.shared.info(.general, "profile_action", metadata: ["source": context.source, "action": action])
        Task { defer { busy = false }; do { try await ProfileRepository.shared.manage(userID, circleID: group.circleId, action: action); if action == "remove" { dismiss() } else { await refresh() } } catch { self.error = error.localizedDescription } }
    }
    private func openChat(video: Bool?) {
        guard !busy else { return }; busy = true
        AppLogger.shared.info(.general, "profile_action", metadata: ["source": context.source, "action": video == nil ? "message" : video == true ? "video" : "call"])
        Task {
            defer { busy = false }
            guard let room = await store.openDirect(userID: userID) else { error = AuthSessionManager.shared.lastError ?? "Could not open chat"; AuthSessionManager.shared.lastError = nil; return }
            if let video { ProfilePresentation.shared.pendingCall = (room, video) }
            else { ProfilePresentation.shared.pendingDestination = room; ProfilePresentation.shared.pendingMinimizeCall = context.source == "call_screen" }
            dismiss()
        }
    }
}
private extension ISO8601DateFormatter {
    static func profileDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
struct ProfileAvatarViewer: View {
    @Environment(\.dismiss) private var dismiss
    let user: User
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var drag = CGSize.zero
    var body: some View {
        ZStack {
            AmbientGlowBackground()
            Group {
                if let url = user.avatarURL { CircleMediaView(media: CircleMedia(url: url), contentMode: .fit) }
                else { CircleAvatar(user: user, size: 240, opensProfile: false) }
            }.scaleEffect(scale * magnification).offset(x: offset.width + drag.width, y: offset.height + drag.height)
                .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }.onEnded { scale = min(5, max(1, scale * $0.magnification)) })
                .simultaneousGesture(DragGesture().updating($drag) { value, state, _ in if scale > 1 { state = value.translation } }.onEnded { if scale > 1 { offset.width += $0.translation.width; offset.height += $0.translation.height } else if $0.translation.height > 100 { dismiss() } })
                .onTapGesture(count: 2) { scale = 1; offset = .zero }
                .accessibilityLabel("Profile photo of \(user.name)")
                .accessibilityAction(named: "Zoom in") { scale = min(5, scale + 1) }
                .accessibilityAction(named: "Reset zoom") { scale = 1; offset = .zero }
        }.overlay(alignment: .topTrailing) { CircleIconButton(symbol: "xmark", label: "Close photo") { dismiss() }.padding(20) }
    }
}
struct ProfileSharedMediaView: View {
    @Environment(\.dismiss) private var dismiss
    let messages: [ChatMessage]
    var body: some View {
        NavigationStack {
            ZStack { AmbientGlowBackground(); ScrollView { GlassEffectContainer(spacing: 14) { VStack(spacing: 14) {
                ForEach(messages) { message in VStack(alignment: .leading, spacing: 10) {
                    if let attachment = message.mediaAttachment { InlineMediaView(attachment: attachment); Text(attachment.fileName).font(.caption).lineLimit(2) }
                    if !message.content.isEmpty { Text(.init(message.content)).textSelection(.enabled) }
                    Text(message.timestamp.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }.padding(16).circleSurface() }
            }.padding(20) } } }.navigationTitle("Shared items").toolbar { Button("Done") { dismiss() } }
        }
    }
}
#Preview("Person card · dark") { UserProfileSheet(userID: "preview", preview: profileCardPreview()).circlePreviewTheme(.aurora) }
#Preview("Person card · light") { UserProfileSheet(userID: "preview", preview: profileCardPreview()).circlePreviewTheme(.daylight) }
#Preview("Avatar zoom · dark") { ProfileAvatarViewer(user: MockData.snapshot().friends[0]).circlePreviewTheme(.aurora) }
#Preview("Avatar zoom · light") { ProfileAvatarViewer(user: MockData.snapshot().friends[0]).circlePreviewTheme(.daylight) }
#Preview("Shared items · dark") { ProfileSharedMediaView(messages: []).circlePreviewTheme(.aurora) }
#Preview("Shared items · light") { ProfileSharedMediaView(messages: []).circlePreviewTheme(.daylight) }

private func profileCardPreview(group: Bool = false) -> PersonCard {
    PersonCard(user: UserProfile(id: "preview", username: "maya_k", displayName: "Maya Kowalski"), isSelf: false, state: "active", kind: "person", verified: true,
        personal: ProfilePersonal(), bio: "Product designer. Collects film cameras and answers voice notes far too late.", pronouns: "she/her", customStatus: "Heads down until 5 pm", timeZone: "Europe/Bucharest", memberSince: Date(timeIntervalSince1970: 1709251200),
        presenceVisible: true, presence: UserPresence(userId: "preview", displayName: "Maya", isOnline: true),
        mutualGroups: [MutualGroup(id: "design", name: "Design Squad")], mutualContacts: Array(MockData.snapshot().friends.prefix(3)), links: ["https://example.com"],
        group: group ? ProfileGroup(circleId: "design", name: "Design Squad", role: "Admin", joinedAt: "2025-03-12T12:00:00.000Z", addedBy: "Andrei N.", restricted: false, canManage: true) : nil,
        canCall: true, canMessage: true, sharedItems: [])
}
#Preview("Group admin card · dark") { UserProfileSheet(userID: "preview", context: ProfileContext(source: "group_members", circleID: "design"), preview: profileCardPreview(group: true)).circlePreviewTheme(.aurora) }
#Preview("Group admin card · light") { UserProfileSheet(userID: "preview", context: ProfileContext(source: "group_members", circleID: "design"), preview: profileCardPreview(group: true)).circlePreviewTheme(.daylight) }
