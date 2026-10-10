import UIKit

/// The picture of a collection share: the app medallion, as on the launch screen.
///
/// It is stored in the share record, where invitations take it from, and given to the system
/// sharing screen directly, which otherwise shows a generic document icon.
enum CollectionShareThumbnail {
    /// PNG data of the medallion.
    ///
    /// Always the light variant, since the invitation is seen on any background, and
    /// scaled to 512 px, since the image is stored in the share record.
    static func imageData() -> Data? {
        let light = UITraitCollection(userInterfaceStyle: .light)
        guard let medallion = UIImage(named: "LaunchMedallion", in: .main, compatibleWith: light) else {
            return nil
        }

        let side: CGFloat = 512
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .pngData { _ in
                medallion.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
    }
}
