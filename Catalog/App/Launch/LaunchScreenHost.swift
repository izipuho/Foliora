import SwiftUI

/// Represents launch screen host data and behavior.
struct LaunchScreenHost: UIViewControllerRepresentable {
    let isApplicationReady: Bool
    let shouldPrepareForOnboarding: Bool
    let onFinished: @MainActor () -> Void
    let onReadyForOnboarding: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> LaunchScreenViewController {
        let viewController = LaunchScreenViewController.instantiate(storyboardName: "LaunchScreen")!
        context.coordinator.viewController = viewController
        context.coordinator.update(
            isApplicationReady: isApplicationReady,
            shouldPrepareForOnboarding: shouldPrepareForOnboarding,
            onFinished: onFinished,
            onReadyForOnboarding: onReadyForOnboarding
        )
        return viewController
    }

    func updateUIViewController(_ uiViewController: LaunchScreenViewController, context: Context) {
        context.coordinator.viewController = uiViewController
        context.coordinator.update(
            isApplicationReady: isApplicationReady,
            shouldPrepareForOnboarding: shouldPrepareForOnboarding,
            onFinished: onFinished,
            onReadyForOnboarding: onReadyForOnboarding
        )
    }

    @MainActor
    final class Coordinator {
        var viewController: LaunchScreenViewController?

        private var didRequestFinish = false
        private var didRequestPrepareForOnboarding = false
        private var onFinished: (@MainActor () -> Void)?
        private var onReadyForOnboarding: (@MainActor () -> Void)?

        func update(
            isApplicationReady: Bool,
            shouldPrepareForOnboarding: Bool,
            onFinished: @escaping @MainActor () -> Void,
            onReadyForOnboarding: @escaping @MainActor () -> Void
        ) {
            self.onFinished = onFinished
            self.onReadyForOnboarding = onReadyForOnboarding

            guard isApplicationReady else { return }

            if shouldPrepareForOnboarding {
                guard !didRequestPrepareForOnboarding else { return }

                didRequestPrepareForOnboarding = true
                let completion: @Sendable () -> Void = { [weak self] in
                    Task { @MainActor in
                        self?.readyForOnboarding()
                    }
                }
                viewController?.prepareForOnboarding(completion: completion)
                return
            }

            guard !didRequestFinish else { return }

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

        private func readyForOnboarding() {
            onReadyForOnboarding?()
        }
    }
}
