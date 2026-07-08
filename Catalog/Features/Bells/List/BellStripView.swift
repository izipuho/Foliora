import SwiftUI

struct BellStripView: View {
    let bells: [BellRecord]
    let screenWidth: CGFloat
    let onSelect: (BellRecord) -> Void

    init(
        bells: [BellRecord],
        screenWidth: CGFloat,
        onSelect: @escaping (BellRecord) -> Void
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
