import SwiftUI

/// Displays a single photo-analysis field suggestion with confidence and an apply action.
struct PhotoSuggestionRow: View {
    let title: String
    let suggestedValue: String
    let confidence: Double
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(confidenceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(suggestedValue)
                .foregroundStyle(.primary)

            HStack {
                Spacer()

                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(String(localized: "common.apply"))
            }
        }
        .padding(.vertical, CatalogMetrics.Spacing.xs)
    }

    private var confidenceLabel: String {
        "\(Int((confidence * 100).rounded()))%"
    }
}
