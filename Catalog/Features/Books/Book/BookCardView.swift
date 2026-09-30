import SwiftUI

#if DEBUG
import CoreData
#endif

/// Displays a book card using Books-specific cover geometry inside the shared catalog slot.
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
        ZStack {
            BookCoverBackdropView(
                cover: book.cover,
                size: cardSize
            )

            layoutContent
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(cardShape)
        .glassEffect(.regular.interactive(), in: cardShape)
    }

    @ViewBuilder
    private var layoutContent: some View {
        switch cardMetrics.layoutMode {
        case .covers:
            coverContent
        case .mini:
            coverContent
        case .compact:
            coverContent
        case .wide:
            wideContent
        case .showcase:
            coverContent
        }
    }

    private var coverContent: some View {
        ZStack {
            BookCoverView(
                cover: book.cover,
                size: foregroundCoverSize
            )
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)

            if let accessoryRowStyle = style.accessoryRow, !accessories.isEmpty {
                CatalogCardAccessoryRow(
                    accessories: accessories,
                    style: accessoryRowStyle,
                    bright: true
                )
                .frame(
                    width: max(cardSize.width - (coverInset * 2), 0),
                    height: max(cardSize.height - (coverInset * 2), 0),
                    alignment: .bottomLeading
                )
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }

    private var wideContent: some View {
        HStack(alignment: .center, spacing: wideSpacing) {
            BookCoverView(
                cover: book.cover,
                size: wideCoverMaximumSize
            )
            .shadow(color: .black.opacity(0.20), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: cardMetrics.contentSpacing) {
                if let titleStyle = style.title {
                    Text(book.title)
                        .font(titleStyle.titleFont)
                        .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                        .lineLimit(titleStyle.titleLineLimit)

                    if titleStyle.showsSubtitle, !authorNames.isEmpty {
                        Text(authorNames)
                            .font(titleStyle.subtitleFont)
                            .foregroundStyle(CatalogMediaContrast.onMediaSecondary)
                            .lineLimit(titleStyle.subtitleLineLimit)
                    }
                }

                Spacer(minLength: cardMetrics.contentSpacing)

                if let accessoryRowStyle = style.accessoryRow, !accessories.isEmpty {
                    CatalogCardAccessoryRow(
                        accessories: accessories,
                        style: accessoryRowStyle,
                        bright: true
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(wideInset)
        .frame(width: cardSize.width, height: cardSize.height)
    }

    private var cardShape: RoundedRectangle {
        CatalogShapes.card(cornerRadius: cardMetrics.cornerRadius)
    }

    private var coverInset: CGFloat {
        min(max(min(cardSize.width, cardSize.height) * 0.035, 4), 10)
    }

    private var foregroundCoverSize: CGSize {
        CGSize(
            width: max(cardSize.width - (coverInset * 2), 0),
            height: max(cardSize.height - (coverInset * 2), 0)
        )
    }

    private var wideInset: CGFloat {
        min(max(cardSize.height * 0.055, 10), 16)
    }

    private var wideSpacing: CGFloat {
        max(cardMetrics.contentSpacing * 2, CatalogMetrics.Spacing.md)
    }

    private var wideCoverMaximumSize: CGSize {
        CGSize(
            width: cardSize.width * 0.38,
            height: max(cardSize.height - (wideInset * 2), 0)
        )
    }

    private var authorNames: String {
        book.authorNames.joined(separator: ", ")
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
        .previewEnvironment(container)
    }
}
#endif
