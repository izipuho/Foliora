import Foundation
import OSLog

/// Signposts and log messages for the launch path, from the first scene task to the catalog.
///
/// Every awaited launch stage is one interval, so an Instruments trace of a stuck launch
/// shows which interval began and never ended. Filter the os_signpost instrument by the
/// `Startup` category to see only these stages.
nonisolated enum StartupSignposts {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "Catalog",
        category: "Startup"
    )

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Catalog",
        category: "Startup"
    )
}
