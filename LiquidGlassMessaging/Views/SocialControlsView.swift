import SwiftUI

enum SocialControlsMode: String, Identifiable { case replies, reports; var id: String { rawValue } }
private struct PrivateRepliesResponse: Decodable, Sendable { let replies: [PrivateStoryReply] }
private struct ModerationReportsResponse: Decodable, Sendable { let reports: [TrollModerationReport] }
private struct SocialControlResult: Decodable, Sendable { let success: Bool }
struct SocialControlsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let mode: SocialControlsMode
    let circleID: String
    var onChange: () -> Void
    @State private var replies: [PrivateStoryReply] = []
    @State private var reports: [TrollModerationReport] = []
    @State private var loading = true
    @State private var error: String?
    @State private var removing: UUID?
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()
                ScrollView {
                    GlassEffectContainer(spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            if loading { ProgressView() }
                            if let error { Text(error).font(.footnote) }
                            if mode == .replies {
                                if !loading && replies.isEmpty { ContentUnavailableView("No private replies yet", systemImage: "bubble.right") }
                                ForEach(replies) { reply in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(reply.sender.name).profileEntry(reply.sender.id, name: reply.sender.name, source: "social_controls").font(.headline)
                                        Text(reply.text).font(.body)
                                        Text(reply.createdAt, style: .relative).font(.caption)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding().circleSurface(radius: 22)
                                }
                            } else {
                                if !loading && reports.isEmpty { ContentUnavailableView("No reports", systemImage: "checkmark.shield") }
                                ForEach(reports) { report in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(report.reason).font(.headline)
                                        Text(report.createdAt, style: .relative).font(.caption)
                                        Button("Remove reported post", role: .destructive) { remove(report) }
                                            .buttonStyle(.glass).tint(theme.destructive).disabled(removing != nil)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding().circleSurface(radius: 22)
                                }
                            }
                        }.padding(20)
                    }
                }
            }
            .navigationTitle(mode == .replies ? "Private story replies" : "Troll Wall reports")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async {
        defer { loading = false }
        guard let token = AuthSessionManager.shared.currentSession?.token, let base = AuthSessionManager.shared.savedServerURL else { return }
        do {
            if mode == .replies {
                replies = try await AccountHTTPClient.shared.request("api/circles/\(circleID)/social/replies", baseURL: base, token: token, as: PrivateRepliesResponse.self).replies
            } else {
                reports = try await AccountHTTPClient.shared.request("api/circles/\(circleID)/social/reports", baseURL: base, token: token, as: ModerationReportsResponse.self).reports
            }
        } catch { self.error = error.localizedDescription }
    }
    private func remove(_ report: TrollModerationReport) {
        guard let token = AuthSessionManager.shared.currentSession?.token, let base = AuthSessionManager.shared.savedServerURL else { return }
        removing = report.id
        Task {
            defer { removing = nil }
            do {
                _ = try await AccountHTTPClient.shared.request("api/circles/\(circleID)/social/trolls/\(report.trollId.uuidString.lowercased())/remove",
                    baseURL: base, token: token, body: Data("{}".utf8), as: SocialControlResult.self)
                reports.removeAll { $0.trollId == report.trollId }; onChange()
            } catch { self.error = error.localizedDescription }
        }
    }
}
#Preview("Replies · dark") { SocialControlsView(mode: .replies, circleID: "", onChange: {}).circlePreviewTheme(.aurora) }
#Preview("Replies · light") { SocialControlsView(mode: .replies, circleID: "", onChange: {}).circlePreviewTheme(.daylight) }
#Preview("Reports · dark") { SocialControlsView(mode: .reports, circleID: "", onChange: {}).circlePreviewTheme(.aurora) }
#Preview("Reports · light") { SocialControlsView(mode: .reports, circleID: "", onChange: {}).circlePreviewTheme(.daylight) }
