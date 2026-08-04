import SwiftUI
import UIKit

/// Disables the system edge-swipe-to-go-back gesture while a screen is on top of
/// the nav stack — it competes with the deck's own horizontal drag-to-rate gesture
/// for the same touches, especially near the left edge. Re-enables itself on
/// disappear so other screens (review, commit, a freshly pushed next-pass deck)
/// keep normal swipe-back behavior.
struct SwipeBackGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = Controller()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
