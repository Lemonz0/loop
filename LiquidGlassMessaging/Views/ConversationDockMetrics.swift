import SwiftUI
import UIKit

private struct ConversationDockContextKey: EnvironmentKey { static let defaultValue: ConversationDockMetrics? = nil }
private struct SharedConversationDockKey: EnvironmentKey { static let defaultValue = false }
private struct ConversationDockHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 60 }
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
    var height: CGFloat = 60
    var input: Binding<String>?
}

/// Reads public native bar geometry; no snapshots or replacement category controls.
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
            guard let tabs = tabBarController, !tabs.isTabBarHidden else { return }
            let bar = tabs.tabBar
            guard !bar.isHidden, bar.bounds.height > 0 else { return }
            let height = max(44, bar.bounds.height - bar.safeAreaInsets.bottom)
            guard abs(metrics.height - height) > 0.5 else { return }
            Task { @MainActor [weak self] in self?.metrics.height = height }
        }
    }
}
