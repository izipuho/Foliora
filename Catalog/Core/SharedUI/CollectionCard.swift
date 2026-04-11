import SwiftUI

struct CollectionCard: View {
    let collection: CollectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(collection.kind.title, systemImage: collection.kind.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(collection.kind.tintColor)

                    Text(collection.name)
                        .font(.title3.bold())

                    Text(collection.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(collection.status.label)
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(collection.status.badgeColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(collection.status.badgeColor)
            }

            HStack(spacing: 12) {
                CollectionMetric(title: "Предметов", value: "\(collection.itemCount)")
                CollectionMetric(title: "Участников", value: "\(collection.collaboratorCount)")
                CollectionMetric(title: "Моя роль", value: collection.role.shortLabel)
            }

            Text(collection.sharingSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct CollectionMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
