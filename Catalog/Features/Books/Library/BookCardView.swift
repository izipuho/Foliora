import SwiftUI

/// Displays a book card using the shared catalog card system.
struct BookCardView: View {
    let book: BookRecord
    let cardSize: CGSize

    private let style: CatalogCardContentStyle
    private let cardMetrics: CatalogCardLayoutMode.CardMetrics

    init(
        book: BookRecord,
        style: CatalogCardContentStyle,
        cardSize: CGSize,
        cardMetrics: CatalogCardLayoutMode.CardMetrics
    ) {
        self.book = book
        self.cardSize = cardSize
        self.style = style
        self.cardMetrics = cardMetrics
    }

    var body: some View {
        CatalogCardContent(
            title: book.title,
            subtitle: authorNames,
            accessories: accessories,
            style: style,
            bright: coverPhoto != nil,
            cardSize: cardSize,
            cardMetrics: cardMetrics
        )
        .catalogSurfaceCard(cardMetrics: cardMetrics) {
            if let coverPhoto {
                MediaPreviewImage(
                    identifier: coverPhoto.localIdentifier,
                    originalData: coverPhoto.originalData,
                    size: cardSize
                )
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
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
            .map(\.person.name)
            .joined(separator: ", ")
    }

    private var accessories: [CatalogCardAccessory] {
        var result: [CatalogCardAccessory] = []

        if let publicationYear = book.details.publicationYear {
            result.append(.chip(String(publicationYear)))
        }

        if let volumeNumber = book.details.volumeNumber {
            result.append(.label(text: String(volumeNumber), systemImage: "books.vertical"))
        }

        return result
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
