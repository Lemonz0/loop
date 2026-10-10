import SwiftUI

struct TrollWallView: View {
    @Environment(\.appTheme) private var theme
    @Bindable var model: CircleViewModel
    @AppStorage("circle_troll_note_dismissed") private var noteDismissed = false
    @State private var composer: CircleComposerKind?
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34.0
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Troll Wall").font(.system(size: titleSize, weight: .bold)).tracking(-0.8)
                                Text("Anonymous. Only your circle sees it.").font(.subheadline).foregroundStyle(theme.secondaryText)
                            }
                            Spacer()
                            CircleIconButton(symbol: "plus", label: "Post anonymously") { composer = .troll }
                        }
                        Button { noteDismissed.toggle() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "hand.raised.fill")
                                Text(noteDismissed ? "Keep it kind" : "Keep it funny, not cruel. Authors are never shown.")
                                    .font(.footnote)
                                Spacer()
                                Image(systemName: noteDismissed ? "chevron.down" : "chevron.up")
                            }.padding(14).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain).circleSurface(radius: 22, interactive: true)
                        .accessibilityLabel(noteDismissed ? "Expand Troll Wall guidelines" : "Collapse Troll Wall guidelines")
                        TrollWallGrid(model: model)
                    }.padding(20).padding(.bottom, 20)
                }.refreshable { await model.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $composer) { CircleComposer(kind: $0, model: model) }
            .task { await model.refresh() }
        }
    }
}

struct TrollWallGrid: View {
    @Bindable var model: CircleViewModel
    private var columns: [[TrollPost]] {
        var columns: [[TrollPost]] = [[], []]
        var heights = [0.0, 0.0]
        for post in model.snapshot.trollPosts {
            let i = heights[0] <= heights[1] ? 0 : 1
            columns[i].append(post); heights[i] += 1 / post.aspectRatio + 0.08
        }
        return columns
    }
    var body: some View {
        if model.snapshot.trollPosts.isEmpty {
            ContentUnavailableView("Your wall is quiet", systemImage: "photo.on.rectangle", description: Text("Share a kind, funny photo with your circle."))
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<2) { column in
                    LazyVStack(spacing: 12) {
                        ForEach(columns[column]) { post in TrollTile(post: post, model: model) }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct TrollTile: View {
    @Environment(\.appTheme) private var theme
    let post: TrollPost
    @Bindable var model: CircleViewModel
    @State private var showReport = false
    var body: some View {
        CircleMediaView(media: CircleMedia(url: post.imageURL, imageData: post.imageData))
            .aspectRatio(post.aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Button { Task { await model.react(post) } } label: {
                    Label("Laughs \(post.reactions)", systemImage: post.hasReacted ? "face.smiling.fill" : "face.smiling")
                        .font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 44)
                }
                .buttonStyle(.plain).circleSurface(radius: 24, interactive: true).padding(8)
                .accessibilityLabel("\(post.hasReacted ? "Remove laugh" : "Laugh"), \(post.reactions) reactions")
            }
            .accessibilityLabel(post.caption.isEmpty ? "Anonymous photo" : post.caption)
            .accessibilityAction(named: "Report post") { showReport = true }
            .contextMenu { Button("Report", systemImage: "flag", role: .destructive) { showReport = true } }
            .confirmationDialog("Report this post?", isPresented: $showReport, titleVisibility: .visible) {
                Button("Bullying or harassment", role: .destructive) { Task { await model.report(post, reason: "Bullying or harassment") } }
                Button("Posted without permission", role: .destructive) { Task { await model.report(post, reason: "Posted without permission") } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The post will be hidden for you and sent for moderation. Its author stays anonymous to your circle.") }
    }
}

#Preview("Troll Wall · dark") { TrollWallView(model: CircleViewModel()).circlePreviewTheme(.aurora) }
#Preview("Troll Wall · light") { TrollWallView(model: CircleViewModel()).circlePreviewTheme(.daylight) }
#Preview("Grid · dark") { TrollWallGrid(model: CircleViewModel()).padding().circlePreviewTheme(.aurora) }
#Preview("Grid · light") { TrollWallGrid(model: CircleViewModel()).padding().circlePreviewTheme(.daylight) }
#Preview("Tile · dark") { TrollTile(post: MockData.snapshot().trollPosts[0], model: CircleViewModel()).frame(width: 180).circlePreviewTheme(.aurora) }
#Preview("Tile · light") { TrollTile(post: MockData.snapshot().trollPosts[0], model: CircleViewModel()).frame(width: 180).circlePreviewTheme(.daylight) }
