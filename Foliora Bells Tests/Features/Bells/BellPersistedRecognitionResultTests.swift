import Foundation
import Testing
@testable import Foliora_Bells

struct BellPersistedRecognitionResultTests {
    @Test
    func roundTripRestoresReviewableSuggestions() throws {
        let suggestions = BellPhotoSuggestions(
            tags: ["ceramic"],
            recognizedText: [],
            visualKeywords: [],
            isBellDetected: true,
            title: SuggestedFieldValue(value: "Bell", confidence: 0.9),
            notes: SuggestedFieldValue(value: "Blue", confidence: 0.8),
            material: SuggestedFieldValue(value: .ceramic, confidence: 0.95),
            condition: SuggestedFieldValue(value: .good, confidence: 0.7),
            customMaterialName: nil,
            suggestedYear: SuggestedFieldValue(value: 2024, confidence: 0.6),
            suggestedGeo: SuggestedFieldValue(
                value: GeoPoint(label: "Paris", name: "Paris", coordinate: nil),
                confidence: 0.5
            ),
            suggestedTags: [
                SuggestedFieldValue(value: "ceramic", confidence: 0.95)
            ],
            debugInfo: nil
        )

        let data = try JSONEncoder().encode(
            BellPersistedRecognitionResult(suggestions: suggestions)
        )
        let restored = try JSONDecoder()
            .decode(BellPersistedRecognitionResult.self, from: data)
            .runtimeSuggestions

        #expect(restored.isBellDetected)
        #expect(restored.title?.value == "Bell")
        #expect(restored.material?.value == .ceramic)
        #expect(restored.condition?.value == .good)
        #expect(restored.suggestedYear?.value == 2024)
        #expect(restored.suggestedGeo?.value.name == "Paris")
        #expect(restored.suggestedTags.map(\.value) == ["ceramic"])
    }
}
