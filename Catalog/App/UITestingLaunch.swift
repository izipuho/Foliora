#if DEBUG
import Foundation

/// Launch mode used by UI tests: in-memory store with fixed data, no CloudKit, no onboarding or splash.
enum UITestingLaunch {
    static let argument = "-ui-testing"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }
}
#endif
