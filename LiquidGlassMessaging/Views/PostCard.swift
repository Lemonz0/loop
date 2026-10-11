import SwiftUI

struct PostTimestamp: View {
    let date: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.label(date, now: context.date))
        }
    }
    static func label(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct PostCard: View {
    @Environment(\.appTheme) private var theme
    let post: Post
    @Bindable var model: CircleViewModel
    @State private var showDetail = false
    @State private var showLikes = false
    @State private var showEdit = false
    @State private var confirmDelete = false
    private var owned: Bool { post.author.id == model.currentUserID }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PostHeader(post: post)
            PostPhotos(post: post).onTapGesture { showDetail = true }
            Text(post.caption).font(.body).onTapGesture { showDetail = true }
            HStack(spacing: 12) {
                Button { Task { await model.like(post) } } label: {
                    Label("\(post.likes)", systemImage: post.isLiked ? "heart.fill" : "heart").frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.glass).disabled(model.isPending(post.id))
                    .accessibilityLabel("\(post.isLiked ? "Unlike" : "Like") post, \(post.likes) likes")
                    .highPriorityGesture(LongPressGesture().onEnded { _ in showLikes = true }, including: owned ? .all : .none)
                    .accessibilityAction(named: "Show likes") { if owned { showLikes = true } }
                Button { showDetail = true } label: {
                    Label("\(post.comments.count)", systemImage: "bubble.right").frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.glass).accessibilityLabel("Comments, \(post.comments.count)")
                Spacer()
            }
        }.padding(16).circleSurface().contentShape(Rectangle())
            .contextMenu {
                if owned {
                    Button("Edit", systemImage: "pencil") { showEdit = true }
                    Button("Who liked this post", systemImage: "heart") { showLikes = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
            .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete post", role: .destructive) { Task { await model.delete(post) } }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showDetail) { PostDetailView(postID: post.id, model: model).profilePresentationHost() }
            .onChange(of: showDetail) { _, presented in if presented { HapticFeedback.soft() } }
            .sheet(isPresented: $showEdit) { EditPostView(post: post, model: model) }
            .sheet(isPresented: $showLikes) { PostLikesView(postID: post.id, model: model).environment(\.profileContext, ProfileContext(source: "reaction")).profilePresentationHost() }
    }
}

private struct PostHeader: View {
    @Environment(\.appTheme) private var theme
    let post: Post
    var fullDate = false
    var body: some View {
        HStack(spacing: 10) {
            CircleAvatar(user: post.author)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.author.name).profileEntry(post.author.id, name: post.author.name, source: "home_feed").font(.headline).lineLimit(1)
                Group {
                    if fullDate { Text(post.createdAt.formatted(date: .abbreviated, time: .shortened)) }
                    else { PostTimestamp(date: post.createdAt) }
                }.font(.caption).foregroundStyle(theme.secondaryText)
            }
            Spacer()
        }
    }
}
struct PostPhotos: View {
    let post: Post
    var height: CGFloat = 290
    var radius: CGFloat = 20
    var onPhotoTap: ((Int) -> Void)?
    var body: some View {
        Group {
            if post.media.count > 1 {
                TabView {
                    ForEach(Array(post.media.enumerated()), id: \.offset) { index, media in photo(media, index: index) }
                }.tabViewStyle(.page(indexDisplayMode: .always))
            } else if let media = post.media.first { photo(media, index: 0) }
        }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityLabel("Photo by \(post.author.name)")
    }
    @ViewBuilder private func photo(_ media: CircleMedia, index: Int) -> some View {
        if let onPhotoTap {
            CircleMediaView(media: media, cachesPost: true).contentShape(Rectangle())
                .onTapGesture { onPhotoTap(index) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Open photo \(index + 1) by \(post.author.name) full screen")
                .accessibilityAction { onPhotoTap(index) }
        } else { CircleMediaView(media: media, cachesPost: true) }
    }
}
private struct EditPostView: View {
    @Environment(\.dismiss) private var dismiss
    let post: Post
    @Bindable var model: CircleViewModel
    @State private var caption: String
    @State private var saving = false
    init(post: Post, model: CircleViewModel) { self.post = post; self.model = model; _caption = State(initialValue: post.caption) }
    var body: some View {
        NavigationStack {
            ZStack { AmbientGlowBackground(); ScrollView { TextField("Description", text: $caption, axis: .vertical).lineLimit(3...12).padding().circleSurface().padding(20) } }
                .navigationTitle("Edit post")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { saving = true; Task { if await model.edit(post, caption: caption) { dismiss() }; saving = false } }.disabled(saving || caption.count > 2000) }
                }.interactiveDismissDisabled(saving)
        }
    }
}
struct PostLikesView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let postID: UUID
    @Bindable var model: CircleViewModel
    @State private var users: [User] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        if loading { ProgressView() }
                        else if let error { Text(error).foregroundStyle(theme.destructive) }
                        else if users.isEmpty { Text("No likes yet") }
                        ForEach(users) { user in HStack { CircleAvatar(user: user); Text(user.name).profileEntry(user.id, name: user.name, source: "reaction"); Spacer() }.padding().circleSurface() }
                    }.padding(20)
                }
            }.navigationTitle("Likes").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .task { do { users = try await model.repository.postLikes(id: postID) } catch { self.error = error.localizedDescription }; loading = false }
        }
    }
}
#Preview("Post · dark") { PostCard(post: MockData.snapshot().posts[0], model: CircleViewModel()).padding().circlePreviewTheme(.aurora) }
#Preview("Post · light") { PostCard(post: MockData.snapshot().posts[0], model: CircleViewModel()).padding().circlePreviewTheme(.daylight) }
#Preview("Post detail · dark") { let model = CircleViewModel(); PostDetailView(postID: model.snapshot.posts[0].id, model: model).circlePreviewTheme(.aurora) }
#Preview("Post detail · light") { let model = CircleViewModel(); PostDetailView(postID: model.snapshot.posts[0].id, model: model).circlePreviewTheme(.daylight) }
#Preview("Edit post · dark") { EditPostView(post: MockData.snapshot().posts[0], model: CircleViewModel()).circlePreviewTheme(.aurora) }
#Preview("Edit post · light") { EditPostView(post: MockData.snapshot().posts[0], model: CircleViewModel()).circlePreviewTheme(.daylight) }
#Preview("Likes · dark") { PostLikesView(postID: UUID(), model: CircleViewModel()).circlePreviewTheme(.aurora) }
#Preview("Likes · light") { PostLikesView(postID: UUID(), model: CircleViewModel()).circlePreviewTheme(.daylight) }
