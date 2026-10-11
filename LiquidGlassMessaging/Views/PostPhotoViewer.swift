import SwiftUI

struct PostPhotoPresentation: Identifiable {
    let id = UUID()
    let media: [CircleMedia]
    let initialIndex: Int
    let authorName: String
}

struct PostPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selection: PostPhotoPresentation
    @State private var index: Int
    @State private var dragOffset: CGFloat = 0

    init(selection: PostPhotoPresentation) {
        self.selection = selection
        _index = State(initialValue: max(0, min(selection.initialIndex, selection.media.count - 1)))
    }

    var body: some View {
        ZStack {
            AmbientGlowBackground()
            if selection.media.isEmpty {
                ContentUnavailableView("Photo unavailable", systemImage: "photo")
            } else {
                TabView(selection: $index) {
                    ForEach(Array(selection.media.enumerated()), id: \.offset) { position, media in
                        CircleMediaView(media: media, contentMode: .fit, cachesPost: true)
                            .tag(position)
                            .accessibilityLabel("Photo \(position + 1) of \(selection.media.count) by \(selection.authorName)")
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                    .offset(y: reduceMotion ? 0 : dragOffset)
                    .ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 24)
            .onChanged { value in
                if value.translation.height > abs(value.translation.width), value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                let vertical = value.translation.height > abs(value.translation.width) * 1.25
                if vertical && (value.translation.height > 100 || value.predictedEndTranslation.height > 200) {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { dragOffset = 0 }
                }
            })
        .overlay(alignment: .topTrailing) {
            GlassEffectContainer(spacing: 14) {
                CircleIconButton(symbol: "xmark", label: "Close photo", compact: true) { dismiss() }
            }.padding(.horizontal, 20).padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if selection.media.count > 1 {
                GlassEffectContainer(spacing: 14) {
                    Text("\(index + 1) of \(selection.media.count)").font(.caption.monospacedDigit())
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glassEffect(.regular, in: Capsule())
                        .accessibilityLabel("Photo \(index + 1) of \(selection.media.count)")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: index = min(index + 1, selection.media.count - 1)
                            case .decrement: index = max(index - 1, 0)
                            @unknown default: break
                            }
                        }
                }.padding(.bottom, 16)
            }
        }
        .accessibilityAction(.escape) { dismiss() }
    }
}

#Preview("Post photo · dark") {
    PostPhotoViewer(selection: PostPhotoPresentation(media: MockData.snapshot().posts[0].media, initialIndex: 0, authorName: "Maya"))
        .circlePreviewTheme(.aurora)
}
#Preview("Post photo · light") {
    PostPhotoViewer(selection: PostPhotoPresentation(media: MockData.snapshot().posts[0].media, initialIndex: 0, authorName: "Maya"))
        .circlePreviewTheme(.daylight)
}
