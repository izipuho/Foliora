import SwiftUI

struct CatalogContainerCard: View {
    let title: String
    var subtitle: String? = nil
    var subtitleTrailing: String? = nil
    var subtitleTrailingIcon: String? = nil
    var footnote: [String] = []
    let systemImage: String
    var accessorySystemImage: String? = nil

    private enum Metrics {
        static let cornerRadius: CGFloat = 24
        static let iconCornerRadius: CGFloat = 18
        static let internalPadding: CGFloat = 16
        static let iconSize: CGFloat = 52
        static let shadowRadius: CGFloat = 14
        static let shadowY: CGFloat = 6
        static let strokeWidth: CGFloat = 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.iconCornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: Metrics.iconSize, height: Metrics.iconSize)

                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title3.bold())

                    HStack(alignment: .firstTextBaseline) {
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }


                        Spacer(minLength: 8)

                        if let subtitleTrailing, let subtitleTrailingIcon {
                            Label(subtitleTrailing, systemImage: subtitleTrailingIcon)
                        }
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

            if !footnote.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(footnote, id: \.self) { detailLine in
                        Text(detailLine)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(Metrics.internalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
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
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.42), lineWidth: Metrics.strokeWidth)
        )
        .shadow(
            color: CatalogSemanticColors.separator.opacity(0.18),
            radius: Metrics.shadowRadius,
            y: Metrics.shadowY
        )
    }
}
