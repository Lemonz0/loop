import SwiftUI
import UIKit

/// Native phone sheets do not dismiss on a backdrop tap by default. Keep their pan gesture
/// and add only a tap recognizer whose delegate rejects every touch inside the sheet.
struct ProfileBackdropDismiss: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> Controller { Controller(onDismiss: { dismiss() }) }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        let onDismiss: () -> Void
        private weak var container: UIView?
        private weak var sheet: UIView?
        private var recognizer: UITapGestureRecognizer?
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            var ancestor: UIViewController = self
            while let parent = ancestor.parent { ancestor = parent }
            guard let presentation = ancestor.presentationController, let container = presentation.containerView, let sheet = presentation.presentedView else { return }
            self.container = container; self.sheet = sheet
            let tap = UITapGestureRecognizer(target: self, action: #selector(close)); tap.delegate = self; tap.cancelsTouchesInView = false
            container.addGestureRecognizer(tap); recognizer = tap
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let sheet, let container else { return false }
            return !sheet.frame.contains(touch.location(in: container))
        }
        @objc private func close() { onDismiss() }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if let recognizer { container?.removeGestureRecognizer(recognizer) }; recognizer = nil
        }
    }
}
