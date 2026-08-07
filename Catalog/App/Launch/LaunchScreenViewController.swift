import UIKit

final class LaunchScreenViewController: UIViewController {
    var onAnimationCompleted: (() -> Void)?

    private var didStartAnimation = false

    private enum Tag {
        static let medallionContainer = 100
        static let medallion = 101
        static let symbol = 102
    }

    private var MedallionContainer: UIView {
        view.viewWithTag(Tag.medallionContainer)!
    }

    private var Medallion: UIImageView {
        view.viewWithTag(Tag.medallion) as! UIImageView
    }

    private var Symbol: UIImageView {
        view.viewWithTag(Tag.symbol) as! UIImageView
    }

    static func instantiate( storyboardName: String, bundle: Bundle = .main ) -> LaunchScreenViewController? {
        let storyboard = UIStoryboard(name: storyboardName, bundle: bundle);
        return storyboard.instantiateInitialViewController { coder in LaunchScreenViewController(coder: coder) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didStartAnimation else { return }
        didStartAnimation = true

        animateSymbol()
    }

    func animateSymbol() {
        let symbol = Symbol
        let angles: [CGFloat] = [10, -7, 4, -2, 0]
        let segmentDuration = 1.0 / Double(angles.count)

        UIView.animateKeyframes(withDuration: 0.9, delay: 0) {
            for (index, angle) in angles.enumerated() {
                UIView.addKeyframe(
                    withRelativeStartTime: Double(index) * segmentDuration,
                    relativeDuration: segmentDuration
                ) {
                    symbol.transform = CGAffineTransform(rotationAngle: angle * .pi / 180)
                }
            }
        } completion: { _ in
            symbol.transform = .identity
            self.onAnimationCompleted?()
        }
    }
}
