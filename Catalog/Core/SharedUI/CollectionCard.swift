import DesignSystem
import SwiftUI

struct CollectionCard: View {
    let collection: CollectionSummary

    var body: some View {
        CatalogGradientCard(colors: collection.backgroundStyle.colors) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    CatalogIconTile(
                        systemImage: collection.kind.systemImage,
                        tint: collection.kind.tintColor
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(collection.name)
                            .font(.title3.bold())

                        Text(collection.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)
                }

                HStack(spacing: 10) {
                    countChip
                    Spacer()
                }
            }
        }
    }

    private var countChip: some View {
        CatalogPill(
            padding: .regular,
            foregroundStyle: AnyShapeStyle(Color.secondary)
        ) {
            Label {
                Text(collection.kind.countLabel(for: collection.itemCount))
            } icon: {
                Image(systemName: "square.stack.3d.up")
            }
            .font(.footnote.weight(.medium))
        }
    }
}
