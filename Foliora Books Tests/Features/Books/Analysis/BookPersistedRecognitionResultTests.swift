import Foundation
import Testing
@testable import Foliora_Books

struct BookPersistedRecognitionResultTests {
    @Test
    func roundTripRestoresSuggestionsAndOCR() throws {
        let suggestions = BookPhotoSuggestions(
            title: SuggestedFieldValue(value: "The Book", confidence: 0.9),
            authors: [SuggestedFieldValue(value: "Author", confidence: 0.8)],
            identifiers: [
                SuggestedFieldValue(
                    value: BookIdentifier(type: .isbn13, value: "9781234567897"),
                    confidence: 0.95
                )
            ],
            publisher: SuggestedFieldValue(value: "Publisher", confidence: 0.7),
            publicationYear: SuggestedFieldValue(value: 2020, confidence: 0.6),
            languageCode: SuggestedFieldValue(value: "en", confidence: 0.9),
            series: nil,
            volumeNumber: nil
        )
        let recognizedText = [
            RecognizedTextFeature(
                text: "The Book",
                confidence: 0.88,
                boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
            )
        ]

        let data = try JSONEncoder().encode(
            BookPersistedRecognitionResult(
                suggestions: suggestions,
                recognizedText: recognizedText
            )
        )
        let persisted = try JSONDecoder()
            .decode(BookPersistedRecognitionResult.self, from: data)

        #expect(persisted.runtimeSuggestions.title?.value == "The Book")
        #expect(persisted.runtimeSuggestions.authors.map(\.value) == ["Author"])
        #expect(persisted.runtimeSuggestions.identifiers.first?.value.type == .isbn13)
        #expect(persisted.runtimeRecognizedText.first?.text == "The Book")
        #expect(persisted.runtimeRecognizedText.first?.boundingBox.width == 0.3)
    }
}
