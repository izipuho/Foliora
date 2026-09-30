import Foundation

/// Tracks whether this device has completed the first launch flow.
///
/// Completion is stored per device in local defaults: translation models are
/// installed per device, so a new device goes through the flow again, while the
/// profile answers synced through iCloud let it skip the introduction step.
///
/// Showing the flow depends only on this record, never on the live state of
/// system services, so a removed translation model or a changed system language
/// does not bring the flow back on the next launch.
enum OnboardingProgress {
    /// Bump when the flow changes enough that every user should see it again.
    static let currentVersion = 1

    private enum Key {
        static let completedVersion = "foliora.onboarding.completedVersion"
        static let resetArgument = "FolioraResetOnboarding"
        static let didCheckLegacyCompletion = "foliora.onboarding.didCheckLegacyCompletion"

        // Keys written by the previous flow, read only to migrate existing users.
        static let legacyTranslationDownloadSkipped = "foliora.onboarding.translationDownloadSkipped"
        static let legacyTranslationCheck = "foliora.translation.lastKnownNeedsDownload"
    }

    private static var defaults: UserDefaults { .standard }

    /// Whether the first launch flow should be shown on this launch.
    ///
    /// Pass `-FolioraResetOnboarding YES` as a launch argument to force the flow.
    static var needsOnboarding: Bool {
        if defaults.bool(forKey: Key.resetArgument) {
            return true
        }

        migrateLegacyCompletionIfNeeded()
        return defaults.integer(forKey: Key.completedVersion) < currentVersion
    }

    /// Records that the flow was completed on this device.
    static func markCompleted() {
        defaults.set(currentVersion, forKey: Key.completedVersion)
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
