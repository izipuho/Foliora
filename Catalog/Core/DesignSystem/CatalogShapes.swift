import SwiftUI

enum CatalogShapes {
    static var capsule: Capsule {
        Capsule()
    }

    static var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous)
    }

    static var thumbnail: RoundedRectangle {
        RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.thumbnail, style: .continuous)
    }

    static var section: RoundedRectangle {
        RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.section, style: .continuous)
    }

    static var medium: RoundedRectangle {
        RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.medium, style: .continuous)
    }
}
