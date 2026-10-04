import Foundation

extension Notification.Name {
    /// Posted when the store changed without the view context taking part, e.g. after a share zone
    /// was purged. The catalog snapshot is reloaded in response.
    static let catalogStoreDidChangeExternally = Notification.Name("FolioraCatalogStoreDidChangeExternally")
}
