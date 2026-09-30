import Foundation

/// Remembers the last translation preparation result checked on this device.
///
/// Launch must not wait for `LanguageAvailability`, which can stall indefinitely.
/// The launch flow reads the last known result synchronously, and the result is
/// refreshed in the background after the app is usable. Translation models are
/// installed per device, so the value lives in local defaults rather than iCloud.
enum TranslationPreparationCache {
    private static let needsDownloadKey = "foliora.translation.lastKnownNeedsDownload"

    /// Whether the last check reported that the translation model must be downloaded.
    ///
    /// Returns `false` when no check has completed yet on this device.
    static var lastKnownNeedsDownload: Bool {
        UserDefaults.standard.bool(forKey: needsDownloadKey)
    }

    /// Stores the result of a completed translation preparation check.
    static func record(_ state: TranslationPreparationState) {
        UserDefaults.standard.set(state == .needsDownload, forKey: needsDownloadKey)
    }
}
