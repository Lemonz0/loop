import Foundation
import Observation

@Observable @MainActor
final class StoryViewerModel {
    private(set) var stories: [Story]
    private(set) var index: Int
    private(set) var elapsed = 0.0
    private(set) var shouldDismiss = false
    var isHeld = false
    var isReplying = false
    var manuallyPaused = false
    var error: String?
    var feedback = 0
    private var lastTick = Date.now
    private var liking = false
    @ObservationIgnored let repository: any FeedRepository
    var current: Story? { stories.indices.contains(index) ? stories[index] : nil }
    var isPaused: Bool { isHeld || isReplying || manuallyPaused || error != nil }
    var progress: Double { min(1, elapsed / 5) }
    init(stories: [Story], startingAt id: UUID, repository: any FeedRepository) {
        let active = stories.filter { $0.isActive(at: .now) }
        self.stories = active; index = active.firstIndex { $0.id == id } ?? 0
        self.repository = repository
    }
    func tick(now: Date = .now, isForeground: Bool) {
        let delta = max(0, min(0.5, now.timeIntervalSince(lastTick)))
        lastTick = now
        guard let current else { shouldDismiss = true; return }
        if !current.isActive(at: now) { advance(); return }
        guard isForeground, !isPaused else { return }
        elapsed += delta
        if elapsed >= 5 { advance() }
    }
    func advance() {
        elapsed = 0; lastTick = .now
        var next = index + 1
        while stories.indices.contains(next), !stories[next].isActive(at: .now) { next += 1 }
        if stories.indices.contains(next) { index = next } else { shouldDismiss = true }
    }
    func previous() {
        elapsed = 0; lastTick = .now
        var previous = index - 1
        while previous >= 0, !stories[previous].isActive(at: .now) { previous -= 1 }
        if previous >= 0 { index = previous }
    }
    func markSeen() async {
        guard let current else { return }
        do { try await repository.markStorySeen(id: current.id) } catch { self.error = error.localizedDescription }
    }
    func like() async {
        guard let current, !liking else { return }
        liking = true; defer { liking = false }
        do {
            try await repository.toggleStoryLike(id: current.id)
            if let i = stories.firstIndex(where: { $0.id == current.id }) { stories[i].isLiked.toggle() }
            feedback += 1
        } catch { self.error = error.localizedDescription }
    }
    func reply(_ text: String) async -> Bool {
        guard let current else { return false }
        do {
            try await repository.reply(storyID: current.id, text: text)
            feedback += 1; return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
