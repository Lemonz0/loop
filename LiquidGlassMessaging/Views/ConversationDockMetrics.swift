import SwiftUI
import UIKit

private struct ConversationDockContextKey: EnvironmentKey { static let defaultValue: ConversationDockMetrics? = nil }
private struct SharedConversationDockKey: EnvironmentKey { static let defaultValue = false }
private struct ConversationDockHeightKey: EnvironmentKey { static let defaultValue = ComposerLayout.barHeight }
extension EnvironmentValues {
    var conversationDockContext: ConversationDockMetrics? {
        get { self[ConversationDockContextKey.self] }
        set { self[ConversationDockContextKey.self] = newValue }
    }
    var usesSharedConversationDock: Bool {
        get { self[SharedConversationDockKey.self] }
        set { self[SharedConversationDockKey.self] = newValue }
    }
    var conversationDockHeight: CGFloat {
        get { self[ConversationDockHeightKey.self] }
        set { self[ConversationDockHeightKey.self] = newValue }
    }
}

@Observable @MainActor
final class ConversationDockMetrics {
    // The conversation and comment composers share the same resting height.
    // UIKit's outer tab-bar frame must never size the input controls.
    let height = ComposerLayout.barHeight
    let bottomMargin: CGFloat = 18
    var bottomOffset: CGFloat = 0
    var input: Binding<String>?
}

/// Converts the window's bottom safe area to the floating dock's screen margin.
struct ConversationDockMeasurement: UIViewControllerRepresentable {
    let metrics: ConversationDockMetrics
    func makeUIViewController(context: Context) -> Controller { Controller(metrics: metrics) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.measure() }
    final class Controller: UIViewController {
        let metrics: ConversationDockMetrics
        init(metrics: ConversationDockMetrics) { self.metrics = metrics; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); measure() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); measure() }
        func measure() {
            guard let window = view.window else { return }
            let bottomOffset = max(0, window.safeAreaInsets.bottom - metrics.bottomMargin)
            guard abs(metrics.bottomOffset - bottomOffset) > 0.5 else { return }
            Task { @MainActor [weak self] in
                self?.metrics.bottomOffset = bottomOffset
            }
        }
    }
}
