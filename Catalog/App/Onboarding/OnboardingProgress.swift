import Foundation

/// Tracks how much of the first launch flow is still due.
///
/// Completion is recorded twice. The record in local defaults says that this
/// device is done. The record in iCloud key-value storage says that the user has
/// been through the flow, on any device; it also survives reinstalling the app.
///
/// A device with only the synced record, such as a second device or a fresh
/// install, does not repeat the flow: only its own setup is left, because
/// translation models are installed per device. The synced record can arrive
/// after the first launch on a new device, which then shows the whole flow.
///
/// What is due depends only on these records, never on the live state of system
/// services, so a removed translation model or a changed system language does
/// not bring the flow back on the next launch.
enum OnboardingProgress {
    /// Bump when the flow changes enough that every user should see it again.
    static let currentVersion = 1

    /// The part of the first launch flow that is still due on this device.
    enum PendingFlow {
        /// Nothing: this device has completed the flow.
        case none
        /// Only this device's own setup: the user has completed the flow elsewhere.
        case deviceSetup
        /// The whole flow.
        case full
    }

    private enum Key {
        /// In local defaults: the flow version completed on this device.
        static let completedVersion = "foliora.onboarding.completedVersion"
        /// In iCloud key-value storage: the flow version the user has completed on any device.
        static let seenVersion = "foliora.onboarding.seenVersion"
        static let resetArgument = "FolioraResetOnboarding"
        static let didCheckLegacyCompletion = "foliora.onboarding.didCheckLegacyCompletion"

        // Keys written by the previous flow, read only to migrate existing users.
        static let legacyTranslationDownloadSkipped = "foliora.onboarding.translationDownloadSkipped"
        static let legacyTranslationCheck = "foliora.translation.lastKnownNeedsDownload"
    }

    private static var defaults: UserDefaults { .standard }
    private static var synced: NSUbiquitousKeyValueStore { .default }

    /// The part of the first launch flow that is due on this launch.
    ///
    /// Pass `-FolioraResetOnboarding YES` as a launch argument to force the whole flow.
    static var pendingFlow: PendingFlow {
        if defaults.bool(forKey: Key.resetArgument) {
            return .full
        }

        migrateLegacyCompletionIfNeeded()

        if defaults.integer(forKey: Key.completedVersion) >= currentVersion {
            // Covers devices that completed the flow before the synced record existed.
            markSeenIfNeeded()
            return .none
        }
        return isSeen ? .deviceSetup : .full
    }

    /// Records that the flow was completed: on this device, and for the user's other devices.
    static func markCompleted() {
        defaults.set(currentVersion, forKey: Key.completedVersion)
        markSeenIfNeeded()
    }

    private static var isSeen: Bool {
        synced.longLong(forKey: Key.seenVersion) >= Int64(currentVersion)
    }

    private static func markSeenIfNeeded() {
        guard !isSeen else { return }
        synced.set(Int64(currentVersion), forKey: Key.seenVersion)
    }

    /// Marks users who finished the previous flow as done, so the update does not replay it.
    ///
    /// A previous run on this device is recognized by the translation check the old
    /// flow recorded; synced profile values alone cannot tell a new device apart.
    /// The check runs once, on the first launch with this flow, so a flow that is
    /// interrupted later is never mistaken for a finished legacy one.
    private static func migrateLegacyCompletionIfNeeded() {
        guard !defaults.bool(forKey: Key.didCheckLegacyCompletion) else { return }
        defaults.set(true, forKey: Key.didCheckLegacyCompletion)

        guard defaults.object(forKey: Key.completedVersion) == nil,
              defaults.object(forKey: Key.legacyTranslationCheck) != nil
        else {
            return
        }

        let translationCompleted = !TranslationPreparationCache.lastKnownNeedsDownload
            || NSUbiquitousKeyValueStore.default.bool(forKey: Key.legacyTranslationDownloadSkipped)

        guard ProfileSettings.isIntroductionAnswered, translationCompleted else { return }
        markCompleted()
    }
}
