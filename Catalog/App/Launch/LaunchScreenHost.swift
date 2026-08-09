import SwiftUI

struct LaunchScreenHost: UIViewControllerRepresentable {
    let isApplicationReady: Bool
    let onFinished: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> LaunchScreenViewController {
        let viewController = LaunchScreenViewController.instantiate(storyboardName: "LaunchScreen")!
        context.coordinator.viewController = viewController
        context.coordinator.update(
            isApplicationReady: isApplicationReady,
            onFinished: onFinished
        )
        return viewController
    }

    func updateUIViewController(_ uiViewController: LaunchScreenViewController, context: Context) {
        context.coordinator.viewController = uiViewController
        context.coordinator.update(
            isApplicationReady: isApplicationReady,
            onFinished: onFinished
        )
    }

    @MainActor
    final class Coordinator {
        var viewController: LaunchScreenViewController?

        private var didRequestFinish = false
        private var onFinished: (@MainActor () -> Void)?

        func update(isApplicationReady: Bool, onFinished: @escaping @MainActor () -> Void) {
            self.onFinished = onFinished

            guard isApplicationReady, !didRequestFinish else { return }

            didRequestFinish = true
            let completion: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in
                    self?.finish()
                }
            }
            viewController?.stopAnimation(completion: completion)
        }

        private func finish() {
            onFinished?()
        }
    }
}
