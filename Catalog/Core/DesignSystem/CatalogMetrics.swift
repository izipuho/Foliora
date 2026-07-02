import SwiftUI

enum CatalogMetrics {

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum CornerRadius {
        static let thumbnail: CGFloat = 12
        static let tile: CGFloat = 16
        static let medium: CGFloat = 18
        static let section: CGFloat = 24
        static let hero: CGFloat = 28
    }

    enum Insets {
        static let screen: CGFloat = 16
        static let overlay: CGFloat = 8
    }
}

//enum CatalogCornerRadii {
//    static let hero: CGFloat = 28
//    static let section: CGFloat = 24
//    static let medium: CGFloat = 18
//    static let tile: CGFloat = 16
//    static let highlight: CGFloat = 14
//    static let thumbnail: CGFloat = 12
//}
//
//enum CatalogLayoutInsets {
//    static let screen: CGFloat = 8 
//    static let overlay: CGFloat = 8 
//}
//
//enum CatalogSpacing {
//    static let micro: CGFloat = 4
//    static let compact: CGFloat = 6
//    static let regular: CGFloat = 12
//    static let section: CGFloat = 24
//}