import SwiftUI

/// Displays the share invitation status overlay interface.
struct ShareInvitationStatusOverlay: View {
    let state: CloudKitShareInvitationAcceptanceState

    var body: some View {
        switch state {
        case .accepting:
            statusCard {
                ProgressView()
                Text("collection.sharing.accepting")
                    .font(CatalogTypography.sectionTitle)
            }
        case .accepted:
            statusCard {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(CatalogSemanticColors.success)
                Text("collection.sharing.access_granted")
                    .font(CatalogTypography.sectionTitle)
            }
        case .acceptedAwaitingSync:
            statusCard {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("collection.sharing.accepted_syncing")
                    .font(CatalogTypography.sectionTitle)
                    .multilineTextAlignment(.center)
            }
        case .idle, .failed:
            EmptyView()
        }
    }

    private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: CatalogMetrics.Spacing.md) {
            content()
        }
        .catalogSurfaceTile()
    }
}
