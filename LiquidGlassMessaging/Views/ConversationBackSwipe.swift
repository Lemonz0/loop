#if os(iOS)
import SwiftUI
import UIKit

/// Enables UIKit's own interactive pop only while the custom chat header is visible.
struct ConversationBackSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        if controller.viewIfLoaded?.window != nil { controller.install() }
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private struct SavedGesture {
            let gesture: UIGestureRecognizer
            weak var delegate: (any UIGestureRecognizerDelegate)?
            let enabled: Bool
        }
        private weak var navigation: UINavigationController?
        private var saved: [SavedGesture] = []
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); restore() }
        func install() {
            guard saved.isEmpty, let navigation = navigationController, navigation.viewControllers.count > 1 else { return }
            self.navigation = navigation
            for gesture in [navigation.interactivePopGestureRecognizer, navigation.interactiveContentPopGestureRecognizer].compactMap({ $0 }) {
                saved.append(SavedGesture(gesture: gesture, delegate: gesture.delegate, enabled: gesture.isEnabled))
                gesture.delegate = self
                gesture.isEnabled = true
            }
        }
        func restore() {
            for state in saved where state.gesture.delegate === self {
                state.gesture.delegate = state.delegate
                state.gesture.isEnabled = state.enabled
            }
            saved = []; navigation = nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touched = touch.view
            while let view = touched {
                if view is UIControl || view is UITextView { return false }
                touched = view.superview
            }
            return true
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation, navigation.viewControllers.count > 1, navigation.transitionCoordinator == nil,
                  viewIfLoaded?.window != nil else { return false }
            if let pan = gestureRecognizer as? UIPanGestureRecognizer {
                let velocity = pan.velocity(in: navigation.view)
                let forward = navigation.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? velocity.x < 0 : velocity.x > 0
                return forward && abs(velocity.x) > abs(velocity.y)
            }
            return true
        }
    }
}
#endif
