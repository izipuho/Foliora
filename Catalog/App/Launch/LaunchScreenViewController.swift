import UIKit

final class LaunchScreenViewController: UIViewController {
    private enum Tag {
        static let medallionBell = 100
        static let medallion = 101
        static let symbol = 102
    }

    private var MedallionBell: UIView {
        view.viewWithTag(Tag.medallionBell)!
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
}
