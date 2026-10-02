import Foundation

/// Remembers the last translation preparation result checked on this device.
///
/// Launch must not wait for `LanguageAvailability`, which can stall indefinitely,
/// so the result is refreshed in the background after the app is usable. Only a
/// device with nothing but its own setup left waits for it, with a time limit.
/// `OnboardingProgress` reads it to recognize devices that finished the previous
/// first launch flow. Translation models are installed per device, so the value
/// lives in local defaults rather than iCloud.
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
