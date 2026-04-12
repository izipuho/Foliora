import SwiftUI

struct CollectionCard: View {
    let collection: CollectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(collection.kind.tintColor.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: collection.kind.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(collection.kind.tintColor)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(collection.kind.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(collection.kind.tintColor)

                        Spacer()

                        Text(collection.status.label)
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(collection.status.badgeColor.opacity(0.16), in: Capsule())
                            .foregroundStyle(collection.status.badgeColor)
                    }

                    Text(collection.name)
                        .font(.title3.bold())

                    Text(collection.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                CollectionMetric(title: "Предметов", value: "\(collection.itemCount)")
                CollectionMetric(title: "Участников", value: "\(collection.collaboratorCount)")
                CollectionMetric(title: "Моя роль", value: collection.role.shortLabel)
            }

            Label(collection.sharingSummary, systemImage: "person.crop.circle.badge.checkmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.94), Color.white.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
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
