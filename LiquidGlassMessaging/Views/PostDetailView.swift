import SwiftUI
import UIKit

struct PostDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let postID: UUID
    @Bindable var model: CircleViewModel
    @State private var text = ""
    @State private var showLikes = false
    @State private var selectedPhoto: PostPhotoPresentation?
    @State private var share: PostShare?
    @State private var preparingShare = false
    @State private var shareError: String?
    @FocusState private var commentFocused: Bool
    private var post: Post? { model.snapshot.posts.first { $0.id == postID } }

    var body: some View {
        ZStack {
            AmbientGlowBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    GlassEffectContainer(spacing: 14) {
                        VStack(alignment: .leading, spacing: 22) {
                            if let post {
                                authorHeader(post)
                                GeometryReader { geometry in
                                    PostPhotos(post: post, height: geometry.size.width, radius: 28) { index in
                                        commentFocused = false
                                        selectedPhoto = PostPhotoPresentation(media: post.media, initialIndex: index, authorName: post.author.name)
                                    }
                                }.aspectRatio(1, contentMode: .fit)
                                actions(post) {
                                    commentFocused = true
                                    proxy.scrollTo("comments", anchor: .top)
                                }
                                (Text(post.author.name).bold() + Text(" " + post.caption))
                                    .font(.body).textSelection(.enabled)
                                comments(post).id("comments")
                            } else {
                                ContentUnavailableView("Post unavailable", systemImage: "photo")
                            }
                        }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 24)
                    }
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let post { composer(post) }
        }
        .sheet(isPresented: $showLikes) { PostLikesView(postID: postID, model: model) }
        .fullScreenCover(item: $selectedPhoto) { selection in
            PostPhotoViewer(selection: selection)
        }
        .popover(item: $share) { item in PostShareSheet(file: item.file, caption: item.caption) }
        .alert("Couldn’t share photo", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK") { shareError = nil }
        } message: { Text(shareError ?? "") }
    }

    private var header: some View {
        GlassEffectContainer(spacing: 14) {
            HStack {
                CircleIconButton(symbol: "chevron.left", label: "Back to Home", compact: true) { dismiss() }
                Spacer()
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }.overlay { Text("Post").font(.title2.bold()).accessibilityAddTraits(.isHeader) }
        }.padding(.horizontal, 20).padding(.vertical, 8)
    }

    private func authorHeader(_ post: Post) -> some View {
        HStack(spacing: 12) {
            CircleAvatar(user: post.author, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(post.author.name).font(.headline).lineLimit(1)
                Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline).foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func actions(_ post: Post, comment: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button { Task { await model.like(post) } } label: {
                Image(systemName: post.isLiked ? "heart.fill" : "heart")
                    .font(.body).frame(width: 28, height: 28)
            }.buttonStyle(.glass).buttonBorderShape(.circle)
                .controlSize(.small).frame(width: 44, height: 44).contentShape(Rectangle())
                .disabled(model.isPending(postID))
                .accessibilityLabel("\(post.isLiked ? "Unlike" : "Like") post, \(post.likes) likes")
                .highPriorityGesture(LongPressGesture().onEnded { _ in showLikes = true },
                    including: post.author.id == model.currentUserID ? .all : .none)
                .accessibilityAction(named: "Show likes") {
                    if post.author.id == model.currentUserID { showLikes = true }
                }
            CircleIconButton(symbol: "bubble.right", label: "Add a comment", compact: true, action: comment)
            Button { Task { await prepareShare(post) } } label: {
                Group {
                    if preparingShare { ProgressView() }
                    else { Image(systemName: "square.and.arrow.up").font(.body) }
                }.frame(width: 28, height: 28)
            }.buttonStyle(.glass).buttonBorderShape(.circle)
                .controlSize(.small).frame(width: 44, height: 44).contentShape(Rectangle())
                .disabled(preparingShare || post.media.isEmpty)
                .accessibilityLabel("Share post photo")
            Spacer(minLength: 0)
        }
    }

    private func comments(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Comments").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("\(post.comments.count)").font(.title3).foregroundStyle(theme.secondaryText)
            }
            if post.comments.isEmpty {
                Text("No comments yet").font(.subheadline).foregroundStyle(theme.secondaryText)
            }
            ForEach(Array(post.comments.enumerated()), id: \.offset) { index, body in
                let author = post.commentDetails.flatMap { $0.indices.contains(index) ? $0[index].author : nil }
                HStack(alignment: .top, spacing: 12) {
                    if let author { CircleAvatar(user: author, size: 40) }
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let author {
                                Text(author.name).font(.subheadline.weight(.semibold)).foregroundStyle(theme.secondaryText)
                            }
                            Text(body).font(.body).textSelection(.enabled)
                        }.padding(.horizontal, 16).padding(.vertical, 12).circleSurface(radius: 22)
                        if let author {
                            Button("Reply") {
                                text = "@\(author.name) "
                                commentFocused = true
                            }.font(.subheadline.weight(.semibold)).foregroundStyle(theme.secondaryText)
                                .frame(minHeight: 44).padding(.leading, 16)
                                .accessibilityLabel("Reply to \(author.name)")
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func composer(_ post: Post) -> some View {
        GlassEffectContainer(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Add a comment", text: $text, axis: .vertical)
                    .font(.body).lineLimit(1...4).focused($commentFocused)
                    .frame(minHeight: 36).padding(.leading, 4)
                    .accessibilityLabel("Add a comment")
                Button {
                    let submitted = text
                    text = ""
                    Task { if !(await model.comment(post, text: submitted)), text.isEmpty { text = submitted } }
                } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.semibold))
                        .frame(width: 34, height: 28)
                }.buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                    .controlSize(.small).frame(width: 50, height: 44).contentShape(Rectangle())
                    .accessibilityLabel("Send comment")
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000 || model.isPending(postID))
            }.padding(.horizontal, 6).padding(.vertical, 3).glassEffect(.regular.interactive(), in: Capsule())
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
    }

    @MainActor private func prepareShare(_ post: Post) async {
        guard !preparingShare, let media = post.media.first else { return }
        preparingShare = true
        defer { preparingShare = false }
        do {
            guard let url = media.url else { throw CircleRepositoryError.emptyMedia }
            let file = try await AuthSessionManager.shared.mediaFile(url)
            try Task.checkCancellation()
            share = PostShare(file: file, caption: post.caption)
        } catch {
            if !AccountHTTPClient.isCancellation(error) { shareError = error.localizedDescription }
        }
    }
}

private struct PostShare: Identifiable {
    let id = UUID()
    let file: URL
    let caption: String
}

private struct PostShareSheet: UIViewControllerRepresentable {
    let file: URL
    let caption: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file, caption], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
