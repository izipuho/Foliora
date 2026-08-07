import UIKit

final class LaunchScreenViewController: UIViewController {
    static func instantiate( storyboardName: String, bundle: Bundle = .main ) -> LaunchScreenViewController? {
        let storyboard = UIStoryboard(name: storyboardName, bundle: bundle);
        return storyboard.instantiateInitialViewController { coder in LaunchScreenViewController(coder: coder) }
    }
}
