import SwiftUI

#if DEBUG
import CoreData
#endif

/// Displays a book card using the shared catalog card system.
struct BookCardView: View {
    let book: BookRecord
    let cardSize: CGSize

    private let style: CatalogCardContentStyle
    private let cardMetrics: CatalogCardLayoutMode.CardMetrics
    private let accessories: [CatalogCardAccessory]

    init(
        book: BookRecord,
        style: CatalogCardContentStyle,
        cardSize: CGSize,
        cardMetrics: CatalogCardLayoutMode.CardMetrics,
        accessories: [CatalogCardAccessory] = []
    ) {
        self.book = book
        self.cardSize = cardSize
        self.style = style
        self.cardMetrics = cardMetrics
        self.accessories = accessories
    }

    var body: some View {
        Group {
            if let coverPhoto {
                mediaContent
                    .catalogSurfaceCard(cardMetrics: cardMetrics) {
                        MediaPreviewImage(
                            identifier: coverPhoto.localIdentifier,
                            originalData: coverPhoto.originalData,
                            size: cardSize
                        )
                    }
            } else {
                CatalogCardContent(
                    title: book.title,
                    subtitle: authorNames,
                    accessories: accessories,
                    style: style,
                    bright: false,
                    cardSize: cardSize,
                    cardMetrics: cardMetrics
                )
                .catalogSurfaceCard(cardMetrics: cardMetrics)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }

    @ViewBuilder
    private var mediaContent: some View {
        if let accessoryRowStyle = style.accessoryRow, !accessories.isEmpty {
            CatalogCardAccessoryRow(
                accessories: accessories,
                style: accessoryRowStyle,
                bright: true
            )
            .frame(
                width: max(cardSize.width - (cardMetrics.cardPadding * 2), 0),
                height: max(cardSize.height - (cardMetrics.cardPadding * 2), 0),
                alignment: .bottomLeading
            )
        } else {
            Color.clear
                .frame(
                    width: max(cardSize.width - (cardMetrics.cardPadding * 2), 0),
                    height: max(cardSize.height - (cardMetrics.cardPadding * 2), 0)
                )
        }
    }

    private var coverPhoto: MediaAsset? {
        book.mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }

    private var authorNames: String {
        book.details.contributors
            .filter { $0.role == .author }
            .sorted { $0.order < $1.order }
            .map(\.person.displayName)
            .joined(separator: ", ")
    }
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBooksMinimal()
    let snapshot = CatalogSnapshot.load(from: container.viewContext)

    if let book = snapshot.bookRecords.first {
        BookCardView(
            book: book,
            style: .compact,
            cardSize: CGSize(width: 220, height: 220),
            cardMetrics: CatalogCardLayoutMode.compact.cardMetrics
        )
        .padding()
    }
}
#endif
