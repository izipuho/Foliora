import SwiftUI

struct BellStripView<Bell: BellCardDisplayable>: View {
    let bells: [Bell]
    let screenWidth: CGFloat
    let onSelect: (Bell) -> Void

    init(
        bells: [Bell],
        screenWidth: CGFloat,
        onSelect: @escaping (Bell) -> Void
    ) {
        self.bells = bells
        self.screenWidth = screenWidth
        self.onSelect = onSelect
    }

    var body: some View {
        let gridMetrics = stripLayoutMode.gridMetrics(forContainerWidth: screenWidth)
        let width = stripLayoutMode.cardWidth(forContainerWidth: screenWidth)
        let cardMetrics = stripLayoutMode.cardMetrics(forCardWidth: width)
        let cardSize = CGSize(width: width, height: cardMetrics.cardHeight)

        CatalogCardStrip(
            cardSize: cardSize,
            spacing: gridMetrics.spacing
        ) { cardSize in
            ForEach(bells, id: \.id) { bell in
                Button {
                    onSelect(bell)
                } label: {
                    BellCardView(
                        bell: bell,
                        layoutMode: stripLayoutMode,
                        cardSize: cardSize,
                        cardMetrics: cardMetrics
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stripLayoutMode: CatalogCardLayoutMode {
        bells.count == 1 ? .wide : .mini
    }
}
