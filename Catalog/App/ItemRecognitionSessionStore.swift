import Foundation

/// Owns in-memory item recognition sessions for the lifetime of the application process.
@MainActor
final class ItemRecognitionSessionStore {
    static let shared = ItemRecognitionSessionStore()

    private struct SessionKey: Hashable {
        let itemID: UUID
        let typeID: ObjectIdentifier
    }

    private var sessions: [SessionKey: AnyObject] = [:]

    private init() {}

    func session<Session: AnyObject>(
        for itemID: UUID,
        as type: Session.Type,
        create: () -> Session
    ) -> Session {
        let key = SessionKey(
            itemID: itemID,
            typeID: ObjectIdentifier(type)
        )

        if let session = sessions[key] as? Session {
            return session
        }

        let session = create()
        sessions[key] = session
        return session
    }

    func discardSession(for itemID: UUID) {
        sessions = sessions.filter { $0.key.itemID != itemID }
    }
}
