import SwiftUI

struct StoriesRow: View {
    @Environment(\.appTheme) private var theme
    let stories: [Story]
    var onCreate: () -> Void
    var onOpen: (Story) -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    Button(action: onCreate) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.title3.weight(.semibold))
                                .frame(width: 62, height: 62)
                                .glassEffect(.regular.interactive(), in: Circle())
                            Text("Your story").font(.caption.weight(.medium))
                            Text("Add a moment").font(.caption2).foregroundStyle(theme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add your story")
                    ForEach(stories.filter { $0.expiresAt > context.date }) { story in
                        Button { onOpen(story) } label: {
                            VStack(spacing: 6) {
                                CircleAvatar(user: story.user, size: 62)
                                    .padding(4)
                                    .overlay {
                                        Circle().strokeBorder(story.isSeen ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(LinearGradient(colors: theme.storyRingColors, startPoint: .topLeading, endPoint: .bottomTrailing)), lineWidth: 2.5)
                                    }
                                Text(story.user.name).profileEntry(story.user.id, name: story.user.name, source: "stories").font(.caption.weight(.medium)).lineLimit(1)
                                Text(story.createdAt, style: .relative).font(.caption2).foregroundStyle(theme.secondaryText)
                            }
                            .frame(width: 76)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(story.user.name)'s story, \(story.isSeen ? "seen" : "unseen")")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 5)
            }
        }
    }
}

#Preview("Stories · dark") { StoriesRow(stories: MockData.snapshot().stories, onCreate: {}, onOpen: { _ in }).circlePreviewTheme(.aurora) }
#Preview("Stories · light") { StoriesRow(stories: MockData.snapshot().stories, onCreate: {}, onOpen: { _ in }).circlePreviewTheme(.daylight) }
