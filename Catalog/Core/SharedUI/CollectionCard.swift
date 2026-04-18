import SwiftUI

struct CollectionCard: View {
    let collection: CollectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous)
                        .fill(collection.kind.tintColor.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: collection.kind.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(collection.kind.tintColor)
                }

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
        .padding(CatalogLayoutInsets.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CatalogCornerRadii.hero, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: collection.backgroundStyle.colors.map { $0.opacity(0.42) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
    }

    private var countChip: some View {
        Label {
            Text(collection.kind.countLabel(for: collection.itemCount))
        } icon: {
            Image(systemName: "square.stack.3d.up")
        }
        .font(.footnote.weight(.medium))
        .catalogPillPadding(.regular)
        .background(.thinMaterial, in: Capsule())
        .foregroundStyle(.secondary)
    }
}
