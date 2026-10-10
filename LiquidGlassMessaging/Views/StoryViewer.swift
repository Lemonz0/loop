import SwiftUI

struct StoryViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var model: StoryViewerModel
    @State private var touchStarted: Date?
    @State private var replyText = ""
    @State private var sending = false
    @State private var replySent = false
    @FocusState private var replyFocused: Bool
    var onFinish: () -> Void
    init(stories: [Story], startingAt id: UUID, repository: any FeedRepository, onFinish: @escaping () -> Void = {}) {
        _model = State(initialValue: StoryViewerModel(stories: stories, startingAt: id, repository: repository))
        self.onFinish = onFinish
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let story = model.current {
                    CircleMediaView(media: story.media).ignoresSafeArea()
                    LinearGradient(colors: theme.storyScrimColors, startPoint: .top, endPoint: .bottom)
                        .frame(height: geometry.size.height * 0.35).frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea().allowsHitTesting(false)
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if touchStarted == nil { touchStarted = .now }
                                model.isHeld = true
                            }
                            .onEnded { value in
                                let duration = Date.now.timeIntervalSince(touchStarted ?? .now)
                                touchStarted = nil; model.isHeld = false
                                if value.translation.height > 100 {
                                    dismiss()
                                } else if duration < 0.25, abs(value.translation.width) < 20, abs(value.translation.height) < 20 {
                                    if replyFocused { replyFocused = false }
                                    else if value.startLocation.x < geometry.size.width / 2 { model.previous() }
                                    else { model.advance() }
                                }
                            })
                        .accessibilityHidden(true)
                    VStack(spacing: 12) {
                        progressBars
                        header(story)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 12)
                    .environment(\.colorScheme, .dark)
                } else {
                    AmbientGlowBackground()
                    ContentUnavailableView("Story expired", systemImage: "clock")
                }
            }
            .contentShape(Rectangle())
            .accessibilityAction(.escape) { dismiss() }
            .accessibilityAction(named: "Pause or resume story") { model.manuallyPaused.toggle() }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.height > 100, abs(value.translation.height) > abs(value.translation.width) {
                    dismiss()
                }
            })
        }
        .safeAreaInset(edge: .bottom, spacing: 14) {
            if let story = model.current {
                VStack(spacing: 14) {
                    if !story.caption.isEmpty {
                        Text(story.caption).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).circleSurface(radius: 24)
                    }
                    HStack(spacing: 12) {
                        HStack {
                            TextField("Reply to \(story.user.name)…", text: $replyText, axis: .vertical)
                                .focused($replyFocused).lineLimit(1...3).submitLabel(.send)
                                .onSubmit { sendReply() }
                                .accessibilityLabel("Private reply to \(story.user.name)")
                            if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button { sendReply() } label: {
                                    Image(systemName: "arrow.up").frame(width: 44, height: 44)
                                }.buttonStyle(.glassProminent).buttonBorderShape(.circle)
                                    .disabled(sending).accessibilityLabel("Send private reply")
                            }
                        }.padding(.leading, 16).padding(.trailing, 6).frame(minHeight: 52).circleSurface(radius: 28)
                        CircleIconButton(symbol: story.isLiked ? "heart.fill" : "heart", label: story.isLiked ? "Unlike story" : "Like story") {
                            Task { await model.like() }
                        }
                    }
                    if replySent { Text("Reply sent privately").font(.caption).padding(8).circleSurface(radius: 12) }
                    if voiceOver {
                        HStack {
                            Button("Previous") { model.previous() }.buttonStyle(.glass)
                            Button("Next") { model.advance() }.buttonStyle(.glass)
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .onChange(of: replyFocused) { _, focused in model.isReplying = focused }
        .onChange(of: model.current?.id) { _, _ in replyText = ""; replySent = false }
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { dismiss() } }
        .onDisappear { onFinish() }
        .task {
            model.manuallyPaused = voiceOver
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                model.tick(isForeground: scenePhase == .active)
            }
        }
        .task(id: model.current?.id) { await model.markSeen() }
        .sensoryFeedback(.success, trigger: model.feedback)
        .alert("Story", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.stories.enumerated()), id: \.element.id) { i, _ in
                GeometryReader { geometry in
                    Capsule().fill(.primary.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.primary)
                                .frame(width: geometry.size.width * (i < model.index ? 1 : i == model.index ? model.progress : 0))
                        }
                }.frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Story \(model.index + 1) of \(model.stories.count)")
    }
    private func header(_ story: Story) -> some View {
        HStack(spacing: 10) {
            CircleAvatar(user: story.user, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(story.user.name).profileEntry(story.user.id, name: story.user.name, source: "social").font(.headline)
                HStack(spacing: 4) {
                    Text(story.createdAt, style: .relative)
                    Text("· disappears in \(max(1, Int(ceil(story.expiresAt.timeIntervalSinceNow / 3600))))h")
                }.font(.caption2)
            }
            Spacer()

        }
    }
    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        Task {
            if await model.reply(text) { replyText = ""; replySent = true; replyFocused = false }
            sending = false
        }
    }
}

#Preview("Story · dark") {
    let snapshot = MockData.snapshot()
    StoryViewer(stories: snapshot.stories, startingAt: snapshot.stories[0].id, repository: MockFeedRepository(snapshot: snapshot)).circlePreviewTheme(.aurora)
}
#Preview("Story · light") {
    let snapshot = MockData.snapshot()
    StoryViewer(stories: snapshot.stories, startingAt: snapshot.stories[0].id, repository: MockFeedRepository(snapshot: snapshot)).circlePreviewTheme(.daylight)
}
