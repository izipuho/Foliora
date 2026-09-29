import Foundation
import os

/// Temporary DEBUG-only diagnostics for media rendering failures.
nonisolated enum MediaDiagnostics {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let availableMB = os_proc_available_memory() / 1_048_576
        print("[Media] \(message()) availableMB=\(availableMB)")
        #endif
    }
}
