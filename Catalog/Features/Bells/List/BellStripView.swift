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
            screenWidth: screenWidth,
            horizontalPadding: 0
        ) { cardSize, cardMetrics in
            ForEach(bells, id: \.id) { bell in
                let style = CatalogCardContentStyle.style(for: stripLayoutMode)

                Button {
                    onSelect(bell)
                } label: {
                    BellCardView(
                        bell: bell,
                        style: style,
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
