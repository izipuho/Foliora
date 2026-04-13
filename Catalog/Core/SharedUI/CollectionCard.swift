import SwiftUI

struct CollectionCard: View {
    let collection: CollectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                    Text(collection.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(collection.kind.tintColor)

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

    private var countChip: some View {
        Label {
            Text("\(collection.itemCount) items")
        } icon: {
            Image(systemName: "square.stack.3d.up")
        }
        .font(.footnote.weight(.medium))
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.04), in: Capsule())
        .foregroundStyle(.secondary)
    }
}
