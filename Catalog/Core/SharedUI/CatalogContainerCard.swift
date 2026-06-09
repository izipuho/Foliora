import SwiftUI

struct CatalogContainerCard: View {
    let title: String
    let subtitle: String?
    let detailLines: [String]
    let systemImage: String
    let accessorySystemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title3.bold())

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)

                if let accessorySystemImage {
                    Image(systemName: accessorySystemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            if !detailLines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(detailLines, id: \.self) { detailLine in
                        Text(detailLine)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(CatalogLayoutInsets.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CatalogCornerRadii.hero, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.18),
                            CatalogSemanticColors.groupedSurfaceElevated.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .catalogShadow(CatalogElevation.collectionCard)
    }
}
