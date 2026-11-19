import CoreHaptics
import OSLog
import SwiftUI

/// The shared haptic vocabulary for catalog actions in every Foliora app.
///
/// Each case describes what happened, not how it feels, so that the same kind of
/// action produces the same feedback on every screen. Most events play system
/// `SensoryFeedback` chosen so that destructive and non-destructive actions are
/// easy to tell apart; a few play a custom Core Haptics pattern from an `.ahap`
/// resource. See "Haptic Feedback" in README.md.
enum CatalogHaptic: Equatable, Sendable {
    /// A user-confirmed, non-destructive action finished (move, save, batch edit).
    case completed
    /// A user-confirmed destructive action finished (delete).
    case destructiveCompleted
    /// A discrete choice changed (picker value, toggle-like state).
    case selectionChanged
    /// Recognition produced suggestions that are now on screen.
    case resultAvailable
    /// The action could not proceed and needs the user's attention (validation).
    case attentionNeeded
    /// The action failed for a reason the user did not cause and cannot fix in place.
    case failed

    /// How an event is rendered.
    enum Playback: Equatable, Sendable {
        /// System feedback played through `sensoryFeedback`.
        case system(SensoryFeedback)
        /// A custom Core Haptics pattern stored as `<name>.ahap` in the app bundle.
        case pattern(named: String)
    }

    /// The feedback played for this event.
    var playback: Playback {
        switch self {
        case .completed:
            return .system(.success)
        case .destructiveCompleted:
            return .system(.impact(weight: .heavy))
        case .selectionChanged:
            return .system(.selection)
        case .resultAvailable:
            return .pattern(named: "RecognitionResult")
        case .attentionNeeded:
            return .system(.warning)
        case .failed:
            return .system(.error)
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
            guard case .system(let feedback) = newValue.haptic?.playback else { return nil }
            return feedback
        }
        .onChange(of: trigger) { _, newValue in
            guard case .pattern(let name) = newValue.haptic?.playback else { return }
            CatalogHapticPatternPlayer.shared.play(patternNamed: name)
        }
    }
}

/// Plays the custom Core Haptics patterns of `CatalogHaptic`.
///
/// Owns one haptics-only engine that shuts down when idle and is recreated after
/// a server reset. Devices without haptics support stay silent.
@MainActor
final class CatalogHapticPatternPlayer {
    static let shared = CatalogHapticPatternPlayer()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Catalog",
        category: "CatalogHaptics"
    )

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?

    private init() {}

    /// Plays the pattern stored as `<name>.ahap` in the main bundle.
    func play(patternNamed name: String) {
        guard supportsHaptics else { return }
        guard let url = Bundle.main.url(forResource: name, withExtension: "ahap") else {
            Self.logger.error("Missing haptic pattern \(name, privacy: .public).ahap")
            return
        }

        do {
            let engine = try runningEngine()
            try engine.playPattern(from: url)
        } catch {
            Self.logger.error("Failed to play haptic pattern \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            engine = nil
        }
    }

    /// Returns the shared engine, creating and starting it when needed.
    private func runningEngine() throws -> CHHapticEngine {
        let engine = try engine ?? makeEngine()
        // Starting an engine that is already running is a no-op; this also
        // restarts it after an automatic idle shutdown.
        try engine.start()
        return engine
    }

    /// Creates a haptics-only engine that does not touch the app's audio session.
    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        // Core Haptics calls this on its own queue; keep the closure nonisolated
        // and hop to the main actor explicitly.
        engine.resetHandler = { @Sendable [weak self] in
            Task { @MainActor in
                self?.engine = nil
            }
        }
        self.engine = engine
        return engine
    }
}
