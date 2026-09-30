import FoundationModels
import SwiftUI

/// Describes one slide of the onboarding introduction to the app's features.
struct OnboardingTourPage: Identifiable, Hashable {
    let id: String
    let systemImage: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    static func == (lhs: OnboardingTourPage, rhs: OnboardingTourPage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Returns the slides for the given collection kind.
    ///
    /// The recognition slide promises model-based suggestions only when
    /// Apple Intelligence is available on this device; otherwise it describes
    /// the analysis that always runs.
    static func pages(
        for kind: CollectionKind,
        isLanguageModelAvailable: Bool = SystemLanguageModel.default.isAvailable
    ) -> [OnboardingTourPage] {
        switch kind {
        case .bells:
            [
                OnboardingTourPage(
                    id: "photos",
                    systemImage: "camera.on.rectangle",
                    title: "onboarding.tour.photos.title",
                    description: "onboarding.tour.photos.bells.description"
                ),
                OnboardingTourPage(
                    id: "recognition",
                    systemImage: "sparkle.magnifyingglass",
                    title: "onboarding.tour.recognition.bells.title",
                    description: isLanguageModelAvailable
                        ? "onboarding.tour.recognition.bells.description_ai"
                        : "onboarding.tour.recognition.bells.description"
                ),
                storage,
                sharing
            ]
        case .books:
            [
                OnboardingTourPage(
                    id: "photos",
                    systemImage: "camera.on.rectangle",
                    title: "onboarding.tour.photos.title",
                    description: "onboarding.tour.photos.books.description"
                ),
                OnboardingTourPage(
                    id: "recognition",
                    systemImage: "text.viewfinder",
                    title: "onboarding.tour.recognition.books.title",
                    description: isLanguageModelAvailable
                        ? "onboarding.tour.recognition.books.description_ai"
                        : "onboarding.tour.recognition.books.description"
                ),
                storage,
                sharing
            ]
        }
    }

    private static var storage: OnboardingTourPage {
        OnboardingTourPage(
            id: "storage",
            systemImage: "house",
            title: "onboarding.tour.storage.title",
            description: "onboarding.tour.storage.description"
        )
    }

    private static var sharing: OnboardingTourPage {
        OnboardingTourPage(
            id: "sharing",
            systemImage: "person.2",
            title: "onboarding.tour.sharing.title",
            description: "onboarding.tour.sharing.description"
        )
    }
}
