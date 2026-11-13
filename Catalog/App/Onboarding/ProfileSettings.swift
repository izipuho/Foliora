import Foundation

/// Reads and writes the user's profile values shared through iCloud key-value storage.
///
/// The display name follows the user across devices, so it lives in
/// `NSUbiquitousKeyValueStore` rather than local defaults.
enum ProfileSettings {
    private enum Key {
        static let displayName = "foliora.profile.displayName"
        static let didSkipIntroduction = "foliora.profile.didSkipIntroduction"
    }

    private static var store: NSUbiquitousKeyValueStore { .default }

    /// The trimmed display name, or `nil` when the user has not set one.
    static var displayName: String? {
        let trimmed = store.string(forKey: Key.displayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// Whether the user chose not to introduce themselves.
    static var didSkipIntroduction: Bool {
        store.bool(forKey: Key.didSkipIntroduction)
    }

    /// Whether the introduction question has been answered, either with a name or by skipping.
    static var isIntroductionAnswered: Bool {
        displayName != nil || didSkipIntroduction
    }

    /// Stores a display name; an empty value removes it.
    static func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            store.removeObject(forKey: Key.displayName)
        } else {
            store.set(trimmed, forKey: Key.displayName)
            store.removeObject(forKey: Key.didSkipIntroduction)
        }
    }

    /// Removes the stored display name.
    static func removeDisplayName() {
        store.removeObject(forKey: Key.displayName)
    }

    /// Records that the user skipped the introduction question.
    static func skipIntroduction() {
        store.set(true, forKey: Key.didSkipIntroduction)
    }
}
