import Foundation

/// Owns in-memory item recognition sessions for the lifetime of the application process.
@MainActor
final class ItemRecognitionSessionStore {
    static let shared = ItemRecognitionSessionStore()

    private var bellSessions: [UUID: BellPhotoAnalysisController] = [:]
    private var bookSessions: [UUID: BookPhotoAnalysisController] = [:]

    private init() {}

    func bellSession(for itemID: UUID) -> BellPhotoAnalysisController {
        if let session = bellSessions[itemID] {
            return session
        }

        let session = BellPhotoAnalysisController()
        bellSessions[itemID] = session
        return session
    }

    func bookSession(for itemID: UUID) -> BookPhotoAnalysisController {
        if let session = bookSessions[itemID] {
            return session
        }

        let session = BookPhotoAnalysisController()
        bookSessions[itemID] = session
        return session
    }

    func discardSession(for itemID: UUID) {
        bellSessions.removeValue(forKey: itemID)
        bookSessions.removeValue(forKey: itemID)
    }
}
