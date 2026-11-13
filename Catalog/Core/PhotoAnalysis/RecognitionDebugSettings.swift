#if DEBUG
import Foundation

/// Provides debug-only controls for making recognition lifecycle behavior observable.
enum RecognitionDebugSettings {
    static let artificialDelaySecondsKey = "debug.recognition.artificialDelaySeconds"

    static var artificialDelaySeconds: Double {
        max(0, UserDefaults.standard.double(forKey: artificialDelaySecondsKey))
    }

    static func waitBeforeAnalysisIfNeeded() async {
        let delay = artificialDelaySeconds
        guard delay > 0 else { return }
        try? await Task.sleep(for: .seconds(delay))
    }
}
#endif
