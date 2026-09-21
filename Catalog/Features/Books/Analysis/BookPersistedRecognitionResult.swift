import CoreGraphics
import Foundation

/// Durable Book recognition payload stored with an item.
struct BookPersistedRecognitionResult: Codable, Sendable {
    struct Suggested<Value: Codable & Sendable>: Codable, Sendable {
        let value: Value
        let confidence: Double

        init(_ suggestion: SuggestedFieldValue<Value>) {
            value = suggestion.value
            confidence = suggestion.confidence
        }

        var runtimeValue: SuggestedFieldValue<Value> {
            SuggestedFieldValue(value: value, confidence: confidence)
        }
    }

    struct RecognizedText: Codable, Sendable {
        let text: String
        let confidence: Double
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ feature: RecognizedTextFeature) {
            text = feature.text
            confidence = feature.confidence
            x = feature.boundingBox.origin.x
            y = feature.boundingBox.origin.y
            width = feature.boundingBox.size.width
            height = feature.boundingBox.size.height
        }

        var runtimeValue: RecognizedTextFeature {
            RecognizedTextFeature(
                text: text,
                confidence: confidence,
                boundingBox: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }

    let title: Suggested<String>?
    let authors: [Suggested<String>]
    let identifiers: [Suggested<BookIdentifier>]
    let publisher: Suggested<String>?
    let publicationYear: Suggested<Int>?
    let languageCode: Suggested<String>?
    let series: Suggested<String>?
    let volumeNumber: Suggested<Int>?
    let recognizedText: [RecognizedText]

    init(
        suggestions: BookPhotoSuggestions,
        recognizedText: [RecognizedTextFeature]
    ) {
        title = suggestions.title.map(Suggested.init)
        authors = suggestions.authors.map(Suggested.init)
        identifiers = suggestions.identifiers.map(Suggested.init)
        publisher = suggestions.publisher.map(Suggested.init)
        publicationYear = suggestions.publicationYear.map(Suggested.init)
        languageCode = suggestions.languageCode.map(Suggested.init)
        series = suggestions.series.map(Suggested.init)
        volumeNumber = suggestions.volumeNumber.map(Suggested.init)
        self.recognizedText = recognizedText.map(RecognizedText.init)
    }

    var runtimeSuggestions: BookPhotoSuggestions {
        BookPhotoSuggestions(
            title: title?.runtimeValue,
            authors: authors.map(\.runtimeValue),
            identifiers: identifiers.map(\.runtimeValue),
            publisher: publisher?.runtimeValue,
            publicationYear: publicationYear?.runtimeValue,
            languageCode: languageCode?.runtimeValue,
            series: series?.runtimeValue,
            volumeNumber: volumeNumber?.runtimeValue
        )
    }

    var runtimeRecognizedText: [RecognizedTextFeature] {
        recognizedText.map(\.runtimeValue)
    }
}
