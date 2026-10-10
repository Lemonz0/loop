import SwiftUI
import UIKit

public struct HomeView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fallbackModel = CircleViewModel()
    private let suppliedModel: CircleViewModel?
    @State private var section: CircleFeedSection = .feed
    @State private var composer: CircleComposerKind?
    @State private var selectedStory: Story?
    @FocusState private var searchFocused: Bool
    @Namespace private var headerNamespace
    @State private var showsSearch = false
    @State private var query = ""
    @State private var controls: SocialControlsMode?
    @State private var auth = AuthSessionManager.shared
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34.0
    private var model: CircleViewModel { suppliedModel ?? fallbackModel }
    public init(model: CircleViewModel? = nil) { suppliedModel = model }

    public var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        homeHeader.padding(.horizontal, 20)
                        StoriesRow(stories: model.snapshot.stories, onCreate: { composer = .story }, onOpen: { selectedStory = $0 })
                        sectionPicker.padding(.horizontal, 20)
                        if section == .feed {
                            GlassEffectContainer(spacing: 14) {
                                LazyVStack(spacing: 14) {
                                    if model.snapshot.posts.isEmpty { ContentUnavailableView("Your feed is quiet", systemImage: "photo", description: Text("Share the first moment with your circle.")) }
                                    ForEach(model.snapshot.posts.filter {
                                        query.isEmpty || $0.caption.localizedCaseInsensitiveContains(query) || $0.author.name.localizedCaseInsensitiveContains(query)
                                    }) { post in PostCard(post: post, model: model) }
                                    trollTeaser
                                }.padding(.horizontal, 20)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Anonymous. Only your circle sees it.").font(.subheadline).foregroundStyle(theme.secondaryText)
                                Text("Keep it funny, not cruel. Authors are never shown.").font(.footnote).padding(14).circleSurface(radius: 22)
                                Button("Post anonymously", systemImage: "plus") { composer = .troll }.buttonStyle(.glassProminent)
                                TrollWallGrid(model: model)
                            }.padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 16).padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await model.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: showsSearch) { if showsSearch { searchFocused = true } }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in if showsSearch { closeSearch() } }
            .onDisappear { closeSearch() }
            .task { await model.refresh() }
            .onChange(of: AppEnvironment.shared.chatStore.accountRevision) { _, _ in Task { await model.refresh() } }
            .sheet(item: $controls) { mode in SocialControlsView(mode: mode, circleID: model.currentCircleID ?? "", onChange: { Task { await model.refresh() } }) }
            .sheet(item: $composer) { CircleComposer(kind: $0, model: model) }
            .fullScreenCover(item: $selectedStory) { story in
                StoryViewer(stories: model.activeStories(at: .now), startingAt: story.id, repository: model.repository) {
                    Task { await model.refresh() }
                }
            }
        }
    }
    private func openSearch() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.35)) { showsSearch = true }
    }
    private func closeSearch() {
        searchFocused = false
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.35)) { showsSearch = false; query = "" }
    }
    private var homeHeader: some View {
        GlassEffectContainer(spacing: 12) {
            if showsSearch {
                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                        .matchedGeometryEffect(id: "magnify", in: headerNamespace)
                    TextField("Search friends and captions", text: $query)
                        .focused($searchFocused).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.done).onSubmit { closeSearch() }.accessibilityLabel("Search your circle")
                    Button { closeSearch() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Close search")
                }.glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("home-search", in: headerNamespace)
                    .glassEffectTransition(reduceMotion ? SwiftUI.GlassEffectTransition.materialize : SwiftUI.GlassEffectTransition.matchedGeometry)
            } else {
                HStack {
                    Text("Loop").font(.system(size: titleSize, weight: .bold)).tracking(-0.8).transition(.opacity)
                    if model.isLive {
                        Menu {
                            ForEach(auth.circles) { circle in
                                Button(circle.name, systemImage: model.currentCircleID == circle.id ? "checkmark" : "person.3") { Task { await model.selectCircle(circle.id) } }
                            }
                        } label: {
                            HStack { Text(auth.circles.first(where: { $0.id == model.currentCircleID })?.name ?? "Your circle"); Image(systemName: "chevron.down") }
                                .font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                                .padding(.horizontal, 14).frame(height: 44)
                        }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: Capsule())
                            .disabled(model.isLoading || model.consentPending).transition(.opacity)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        Button { openSearch() } label: {
                            Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                                .matchedGeometryEffect(id: "magnify", in: headerNamespace)
                        }.accessibilityLabel("Search your circle")
                        Menu {
                            Button("Share a post", systemImage: "photo") { composer = .post }
                            Button("Add your story", systemImage: "plus.circle") { composer = .story }
                            Button("Post to Troll Wall", systemImage: "theatermasks") { composer = .troll }
                            if model.isLive {
                                Button("Private story replies", systemImage: "bubble.left.and.bubble.right") { controls = .replies }
                                if auth.circles.first(where: { $0.id == model.currentCircleID })?.ownerId == auth.currentSession?.user.id {
                                    Button("Review Troll Wall reports", systemImage: "flag") { controls = .reports }
                                }
                            }
                        } label: { Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 44, height: 44) }
                            .accessibilityLabel("Create")
                    }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: Capsule())
                        .glassEffectID("home-search", in: headerNamespace)
                        .glassEffectTransition(reduceMotion ? SwiftUI.GlassEffectTransition.materialize : SwiftUI.GlassEffectTransition.matchedGeometry)
                }
            }
        }.frame(minHeight: 44)
    }
    private var sectionPicker: some View {
        GlassEffectContainer(spacing: 12) {
            Picker("Home category", selection: $section) {
                ForEach(CircleFeedSection.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(minHeight: 44)
        }
    }
    private var trollTeaser: some View {
        HStack(spacing: 12) {
            Image(systemName: "theatermasks.fill").font(.title2).foregroundStyle(theme.accent)
                .frame(width: 48, height: 48).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Troll Wall").font(.headline)
                Text("\(model.snapshot.trollPosts.count) anonymous posts in your circle")
                    .font(.caption).foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Button("Post") { composer = .troll }.buttonStyle(.glassProminent).frame(minHeight: 44)
        }.padding(16).circleSurface().contentShape(Rectangle()).onTapGesture { section = .troll }
    }
}

private enum CircleFeedSection: String, CaseIterable, Identifiable {
    case feed = "Feed", troll = "Troll Wall"
    var id: String { rawValue }
}

#Preview("Home · dark") { HomeView().circlePreviewTheme(.aurora) }
#Preview("Home · light") { HomeView().circlePreviewTheme(.daylight) }
