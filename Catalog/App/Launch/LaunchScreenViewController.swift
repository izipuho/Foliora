import UIKit

final class LaunchScreenViewController: UIViewController {
    private var didStartAnimation = false
    private var isAnimatingSymbol = false
    private var didRequestStopAnimation = false
    private var didStopAnimation = false
    private var stopAnimationCompletions: [() -> Void] = []
    private let displayName = NSUbiquitousKeyValueStore.default
        .string(forKey: "foliora.profile.displayName")
    private let greetingLabel = UILabel()

    private enum IntroAnimation {
        static let scale: CGFloat = 0.75
        static let verticalOffsetMultiplier: CGFloat = 0.5
        static let duration: TimeInterval = 0.6
    }

    private enum Tag {
        static let medallionContainer = 100
        static let medallion = 101
        static let symbol = 102
        static let arcs = 200
        static let arcLeft = 201
        static let arcRight = 202
    }

    private var MedallionContainer: UIView {
        view.viewWithTag(Tag.medallionContainer)!
    }

    //private var Medallion: UIImageView {
    //    view.viewWithTag(Tag.medallion) as! UIImageView
    //}

    private var Symbol: UIImageView {
        view.viewWithTag(Tag.symbol) as! UIImageView
    }

    private var Arcs: UIView {
        view.viewWithTag(Tag.arcs)!
    }

    static func instantiate( storyboardName: String, bundle: Bundle = .main ) -> LaunchScreenViewController? {
        let storyboard = UIStoryboard(name: storyboardName, bundle: bundle);
        return storyboard.instantiateInitialViewController { coder in LaunchScreenViewController(coder: coder) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        greetingLabel.translatesAutoresizingMaskIntoConstraints = false
        greetingLabel.textAlignment = .center
        greetingLabel.numberOfLines = 1
        greetingLabel.text = greetingText()
        greetingLabel.font = .systemFont(ofSize: 50)
        greetingLabel.textColor = UIColor(named: "LightAccent", in: .main, compatibleWith: nil)
        view.addSubview(greetingLabel)

        NSLayoutConstraint.activate([
            greetingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            greetingLabel.bottomAnchor.constraint(equalTo: Arcs.topAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didStartAnimation else { return }
        didStartAnimation = true

        animateIntro()
    }

    private func animateIntro() {
        let medallionContainer = MedallionContainer
        let verticalOffset = -IntroAnimation.verticalOffsetMultiplier * medallionContainer.bounds.height

        UIView.animate(
            withDuration: IntroAnimation.duration,
            delay: 0,
            options: [.curveEaseInOut]
        ) {
            medallionContainer.transform = CGAffineTransform(
                translationX: 0,
                y: verticalOffset
            ).scaledBy(
                x: IntroAnimation.scale,
                y: IntroAnimation.scale
            )
        } completion: { [weak self] _ in
            self?.animateSymbol()
        }
    }

    private func greetingText() -> String {
        guard let url = Bundle.main.url(forResource: "GreetingsKeys", withExtension: "plist"),
              let suffixes = NSArray(contentsOf: url) as? [String],
              let suffix = suffixes.randomElement()
        else {
            return ""
        }

        let name = displayName.map {
            String.localizedStringWithFormat(String(localized: "splash.greeting_name"), $0)
        } ?? ""
        let greetingKey = "splash.greeting.\(suffix)"
        return String.localizedStringWithFormat(String(localized: LocalizedStringResource(stringLiteral: greetingKey)), name)
    }

    func animateSymbol() {
        guard !didRequestStopAnimation else {
            completeStopAnimation()
            return
        }

        isAnimatingSymbol = true

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
        } completion: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.Symbol.transform = .identity
                self.isAnimatingSymbol = false

                if self.didRequestStopAnimation {
                    self.completeStopAnimation()
                } else {
                    self.animateSymbol()
                }
            }
        }
    }

    func stopAnimation(completion: @escaping () -> Void) {
        guard !didStopAnimation else {
            completion()
            return
        }

        stopAnimationCompletions.append(completion)
        didRequestStopAnimation = true

        if !isAnimatingSymbol {
            completeStopAnimation()
        }
    }

    private func completeStopAnimation() {
        guard !didStopAnimation else { return }

        Symbol.transform = .identity
        didStopAnimation = true

        let completions = stopAnimationCompletions
        stopAnimationCompletions.removeAll()
        completions.forEach { $0() }
    }
}
