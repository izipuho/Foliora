import Foundation

extension Notification.Name {
    /// Posted when the store changed without the view context taking part, e.g. after a share zone
    /// was purged. The catalog snapshot is reloaded in response.
    static let catalogStoreDidChangeExternally = Notification.Name("FolioraCatalogStoreDidChangeExternally")

    /// Posted when leaving a shared collection failed, so the user can be told.
    static let collectionRemovalDidFail = Notification.Name("FolioraCollectionRemovalDidFail")
}
