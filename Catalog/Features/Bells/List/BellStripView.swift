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
        CatalogCardStrip(
            layoutMode: stripLayoutMode,
            screenWidth: screenWidth
        ) { cardSize, cardMetrics in
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
