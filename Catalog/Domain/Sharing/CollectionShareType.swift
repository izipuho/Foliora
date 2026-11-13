import CloudKit
import Foundation

/// Marks a CloudKit share with the kind of collection it carries.
///
/// Foliora apps share one CloudKit container, so the system can hand a share invitation
/// to any of them. The marker lets an app tell an invitation meant for a sibling app
/// before accepting it.
enum CollectionShareType {
    private static let prefix = "com.izipuho.foliora.collection."

    /// The value stored in the share for a collection of the given kind.
    static func value(for kind: CollectionKind) -> String {
        prefix + kind.rawValue
    }

    /// The collection kind recorded in the share, or `nil` for shares created before the marker existed.
    static func kind(of share: CKShare) -> CollectionKind? {
        guard let value = share[CKShare.SystemFieldKey.shareType] as? String,
              value.hasPrefix(prefix)
        else {
            return nil
        }

        return CollectionKind(rawValue: String(value.dropFirst(prefix.count)))
    }
}
