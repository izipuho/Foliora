import SwiftUI

/// The shared haptic vocabulary for catalog actions in every Foliora app.
///
/// Each case describes what happened, not how it feels, so that the same kind of
/// action produces the same feedback on every screen. The concrete
/// `SensoryFeedback` values are chosen so that destructive and non-destructive
/// actions are easy to tell apart. See "Haptic feedback" in README.md.
enum CatalogHaptic: Equatable, Sendable {
    /// A user-confirmed, non-destructive action finished (move, save, batch edit).
    case completed
    /// A user-confirmed destructive action finished (delete).
    case destructiveCompleted
    /// A discrete choice changed (picker value, toggle-like state).
    case selectionChanged
    /// Background work produced a result the user may want to look at (recognition suggestions).
    case resultAvailable
    /// The action could not proceed and needs the user's attention (validation).
    case attentionNeeded
    /// The action failed for a reason the user did not cause and cannot fix in place.
    case failed

    /// The system feedback played for this event.
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .completed:
            return .success
        case .destructiveCompleted:
            return .impact(weight: .heavy)
        case .selectionChanged:
            return .selection
        case .resultAvailable:
            return .impact(weight: .light)
        case .attentionNeeded:
            return .warning
        case .failed:
            return .error
        }
    }
}

/// View state that plays `CatalogHaptic` events through one `.catalogHaptics(_:)` modifier.
///
/// Every call to `play(_:)` produces a new value, so repeating the same event
/// triggers the feedback again.
struct CatalogHapticTrigger: Equatable, Sendable {
    private(set) var haptic: CatalogHaptic?
    private var count = 0

    /// Requests the given haptic event.
    mutating func play(_ haptic: CatalogHaptic) {
        self.haptic = haptic
        count &+= 1
    }
}

extension View {
    /// Plays the latest haptic event requested on `trigger`.
    func catalogHaptics(_ trigger: CatalogHapticTrigger) -> some View {
        sensoryFeedback(trigger: trigger) { _, newValue in
            newValue.haptic?.sensoryFeedback
        }
    }
}
