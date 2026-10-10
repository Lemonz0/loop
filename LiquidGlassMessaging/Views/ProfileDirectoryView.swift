import SwiftUI

struct ProfileDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    let room: ChatRoom?
    @State private var search = ""
    @State private var store = AppEnvironment.shared.chatStore
    @State private var requests: [User] = []
    @State private var error: String?
    private var users: [User] {
        store.memberProfiles.values.filter { user in
            (room == nil || room!.participantIds.contains(user.id)) && (search.isEmpty || user.name.localizedCaseInsensitiveContains(search))
        }.sorted { $0.name < $1.name }
    }
    var body: some View {
        NavigationStack {
            ZStack { AmbientGlowBackground(); ScrollView { GlassEffectContainer(spacing: 14) { VStack(spacing: 14) {
                if room == nil && !requests.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Contact requests").font(.headline)
                        ForEach(requests) { user in
                            HStack { Text(user.name).profileEntry(user.id, name: user.name); Spacer(); Button("Accept") { accept(user) }.buttonStyle(.glassProminent) }
                        }
                    }.padding(16).circleSurface()
                }
                if let error { Text(error).font(.footnote) }
                if users.isEmpty { ContentUnavailableView("No people found", systemImage: "person.2") }
                ForEach(users) { user in
                    HStack(spacing: 12) { CircleAvatar(user: user, opensProfile: false); Text(user.name).font(.headline); Spacer(); Image(systemName: "chevron.right") }
                        .padding(16).circleSurface(interactive: true).profileEntry(user.id, name: user.name)
                }
            }.padding(20) } } }.navigationTitle(room == nil ? "Contacts" : "Group members")
                .searchable(text: $search, prompt: "Search people")
                .toolbar { Button("Done") { dismiss() } }
        }.task { if room == nil { await loadRequests() } }.environment(\.profileContext, ProfileContext(source: room == nil ? "contacts_search" : "group_members", roomID: room?.id,
            circleID: room.flatMap { room in AuthSessionManager.shared.circles.first { $0.roomId == room.id }?.id }))
            .profilePresentationHost()
    }
    private func loadRequests() async {
        struct Response: Decodable, Sendable { let users: [User] }
        do { let response: Response = try await ProfileRepository.shared.request("api/profiles/requests"); requests = response.users }
        catch { self.error = error.localizedDescription }
    }
    private func accept(_ user: User) {
        Task { do { _ = try await ProfileRepository.shared.perform(user.id, action: ProfileAction(action: "contact", value: true), context: ProfileContext()); await loadRequests() } catch { self.error = error.localizedDescription } }
    }
}
struct LoopCallHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var calls: [LoopCallRecord] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ZStack { AmbientGlowBackground(); ScrollView { GlassEffectContainer(spacing: 14) { VStack(spacing: 14) {
                if let error { Text(error).foregroundStyle(theme.secondaryText); Button("Retry") { Task { await load() } }.buttonStyle(.glass) }
                if calls.isEmpty && error == nil { ContentUnavailableView("No calls yet", systemImage: "phone") }
                ForEach(calls) { call in
                    VStack(alignment: .leading, spacing: 14) {
                        Label(call.date.formatted(date: .abbreviated, time: .shortened), systemImage: call.isVideo ? "video" : "phone").font(.caption)
                        ForEach(call.users) { user in HStack { CircleAvatar(user: user); Text(user.name).profileEntry(user.id, name: user.name); Spacer() } }
                    }.padding(16).circleSurface()
                }
            }.padding(20) } } }.navigationTitle("Call history").toolbar { Button("Done") { dismiss() } }.task { await load() }
        }.environment(\.profileContext, ProfileContext(source: "call_history")).profilePresentationHost()
    }
    private func load() async {
        struct Response: Decodable, Sendable { let calls: [LoopCallRecord] }
        do { let response: Response = try await ProfileRepository.shared.request("api/calls/history"); calls = response.calls.reversed(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
#Preview("Directory · dark") { ProfileDirectoryView(room: nil).circlePreviewTheme(.aurora) }
#Preview("Directory · light") { ProfileDirectoryView(room: nil).circlePreviewTheme(.daylight) }
#Preview("Call history · dark") { LoopCallHistoryView().circlePreviewTheme(.aurora) }
#Preview("Call history · light") { LoopCallHistoryView().circlePreviewTheme(.daylight) }
