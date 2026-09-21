import Foundation

/// Durable Bell recognition payload stored with an item.
struct BellPersistedRecognitionResult: Codable, Sendable {
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

    struct GeoValue: Codable, Sendable {
        let label: String
        let name: String
        let latitude: Double?
        let longitude: Double?

        init(_ point: GeoPoint) {
            label = point.label
            name = point.name
            latitude = point.coordinate?.latitude
            longitude = point.coordinate?.longitude
        }

        var runtimeValue: GeoPoint {
            let coordinate: CLLocationCoordinate2D?
            if let latitude, let longitude {
                coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            } else {
                coordinate = nil
            }
            return GeoPoint(label: label, name: name, coordinate: coordinate)
        }
    }

    let isBellDetected: Bool
    let title: Suggested<String>?
    let notes: Suggested<String>?
    let material: Suggested<BellMaterial>?
    let condition: Suggested<ItemCondition>?
    let customMaterialName: Suggested<String>?
    let suggestedYear: Suggested<Int>?
    let suggestedGeo: Suggested<GeoValue>?
    let suggestedTags: [Suggested<String>]

    init(suggestions: BellPhotoSuggestions) {
        isBellDetected = suggestions.isBellDetected
        title = suggestions.title.map(Suggested.init)
        notes = suggestions.notes.map(Suggested.init)
        material = suggestions.material.map(Suggested.init)
        condition = suggestions.condition.map(Suggested.init)
        customMaterialName = suggestions.customMaterialName.map(Suggested.init)
        suggestedYear = suggestions.suggestedYear.map(Suggested.init)
        suggestedGeo = suggestions.suggestedGeo.map {
            Suggested<GeoValue>(
                value: GeoValue($0.value),
                confidence: $0.confidence
            )
        }
        suggestedTags = suggestions.suggestedTags.map(Suggested.init)
    }

    var runtimeSuggestions: BellPhotoSuggestions {
        let runtimeTags = suggestedTags.map(\.runtimeValue)
        return BellPhotoSuggestions(
            tags: runtimeTags.map(\.value),
            recognizedText: [],
            visualKeywords: [],
            isBellDetected: isBellDetected,
            title: title?.runtimeValue,
            notes: notes?.runtimeValue,
            material: material?.runtimeValue,
            condition: condition?.runtimeValue,
            customMaterialName: customMaterialName?.runtimeValue,
            suggestedYear: suggestedYear?.runtimeValue,
            suggestedGeo: suggestedGeo.map {
                SuggestedFieldValue(
                    value: $0.value.runtimeValue,
                    confidence: $0.confidence
                )
            },
            suggestedTags: runtimeTags,
            debugInfo: nil
        )
    }
}

private extension BellPersistedRecognitionResult.Suggested {
    init(value: Value, confidence: Double) {
        self.value = value
        self.confidence = confidence
    }
}
