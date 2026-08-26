import SwiftUI

/// Displays collection sharing status in a catalog dashboard card.
struct CatalogDashboardSharingCard: View {
    let state: CollectionSharingState
    let tint: Color

    private enum Layout {
        static let textSpacing: CGFloat = 2
        static let iconFontSize: CGFloat = 24
    }

    @ViewBuilder
    var body: some View {
        if let content {
            DashboardCard {
                Image(systemName: content.systemImage)
                    .font(.system(size: Layout.iconFontSize, weight: .semibold))
                    .foregroundStyle(tint)
            } content: {
                VStack(alignment: .leading, spacing: Layout.textSpacing) {
                    Text(String(localized: "bell_catalog.dashboard.sharing"))
                        .font(CatalogTypography.sectionTitle)
                    Text(content.value)
                        .font(CatalogTypography.cardSubtitle)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let detail = content.detail {
                        Text(detail)
                            .font(CatalogTypography.chipLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    private var content: Content? {
        switch state.currentUserRole {
        case .owner:
            return Content(
                systemImage: "person.2.fill",
                value: state.isShared
                    ? localizedParticipantsCount
                    : String(localized: "collection.sharing.status.private"),
                detail: pendingInvitationsDetail
            )
        case .contributor:
            return Content(
                systemImage: "person.crop.circle.badge.checkmark",
                value: String(localized: "collection.sharing.role.coowner"),
                detail: nil
            )
        case .viewer:
            return Content(
                systemImage: "eye.fill",
                value: String(localized: "collection.sharing.role.viewer"),
                detail: nil
            )
        }
    }

    private var localizedParticipantsCount: String {
        String.localizedStringWithFormat(
            String(localized: "collection.sharing.participants_count"),
            state.acceptedParticipantsCount
        )
    }

    private var pendingInvitationsDetail: String? {
        guard !state.invitedParticipants.isEmpty else { return nil }

        return String.localizedStringWithFormat(
            String(localized: "bell_catalog.dashboard.sharing.pending_invitations_count"),
            state.invitedParticipants.count
        )
    }

    private struct Content {
        let systemImage: String
        let value: String
        let detail: String?
    }
}
