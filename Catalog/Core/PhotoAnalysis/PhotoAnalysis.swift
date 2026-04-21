import Foundation
import MapKit
import UIKit
import Vision

struct SuggestedFieldValue<Value: Sendable>: Sendable {
    let value: Value
    let confidence: Double
}

struct VisionFeature: Sendable {
    let label: String
    let confidence: Double
}

struct RecognizedTextFeature: Hashable, Sendable {
    let text: String
    let confidence: Double
}

struct VisualKeyword: Hashable, Sendable {
    let value: String
    let confidence: Double
}

struct GeoPoint: Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
}

enum PhotoSemanticTag: String, CaseIterable, Hashable, Sendable {
    case bell
    case metal
    case brass
    case bronze
    case ceramic
    case porcelain
    case glass
    case wood
    case silver
    case stone
    case plastic
    case decorative
    case antique
    case vintage
    case shiny
    case worn
    case damaged
}

struct NormalizedVisionTag: Hashable, Sendable {
    let tag: PhotoSemanticTag
    let confidence: Double
}

struct PhotoAnalysisResult: Sendable {
    let tags: [String]
    let year: Int?
    let geo: GeoPoint?

    let visionFeatures: [VisionFeature]
    let normalizedTags: [NormalizedVisionTag]
    let recognizedText: [RecognizedTextFeature]
    let visualKeywords: [VisualKeyword]

    static let empty = PhotoAnalysisResult(
        tags: [],
        year: nil,
        geo: nil,
        visionFeatures: [],
        normalizedTags: [],
        recognizedText: [],
        visualKeywords: []
    )
}

protocol VisionFeatureExtracting: Sendable {
    func extractFeatures(from image: UIImage) async throws -> [VisionFeature]
}

protocol TextFeatureExtracting: Sendable {
    func extractText(from image: UIImage) async throws -> [RecognizedTextFeature]
}

protocol PhotoAnalysisService: Sendable {
    func analyze(image: UIImage) async -> PhotoAnalysisResult
}

struct VisionFeatureExtractor: VisionFeatureExtracting {
    private let maxResults: Int
    private let minimumConfidence: Double

    init(maxResults: Int = 16, minimumConfidence: Double = 0.18) {
        self.maxResults = maxResults
        self.minimumConfidence = minimumConfidence
    }

    func extractFeatures(from image: UIImage) async throws -> [VisionFeature] {
        guard let cgImage = image.cgImage else { return [] }

        var features: [VisionFeature] = []
        let classifyRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([classifyRequest])

        let classifications: [VNClassificationObservation] = classifyRequest.results ?? []
        features += classifications.map { VisionFeature(label: $0.identifier.lowercased(), confidence: Double($0.confidence)) }

        if #available(iOS 26.0, *), let objectRequest = makeRecognizeObjectsRequest() {
            try handler.perform([objectRequest])
            let objects = (objectRequest as NSObject).value(forKey: "results") as? [VNRecognizedObjectObservation] ?? []
            features += objects.flatMap { observation in
                observation.labels.map { label in
                    VisionFeature(label: label.identifier.lowercased(), confidence: Double(label.confidence))
                }
            }
        }

        return deduplicate(features)
            .filter { $0.confidence >= minimumConfidence }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(maxResults)
            .map { $0 }
    }

    private func deduplicate(_ features: [VisionFeature]) -> [VisionFeature] {
        features.reduce(into: [String: VisionFeature]()) { partialResult, feature in
            let key = feature.label.lowercased()
            if partialResult[key] == nil || partialResult[key]!.confidence < feature.confidence {
                partialResult[key] = feature
            }
        }
        .values
        .map { $0 }
    }

    private func makeRecognizeObjectsRequest() -> VNRequest? {
        guard let requestClass = NSClassFromString("VNRecognizeObjectsRequest") as? NSObject.Type else {
            return nil
        }
        return requestClass.init() as? VNRequest
    }
}

struct VisionTextFeatureExtractor: TextFeatureExtracting {
    private let maxResults: Int
    private let minimumConfidence: Double

    init(maxResults: Int = 24, minimumConfidence: Double = 0.0) {
        self.maxResults = maxResults
        self.minimumConfidence = minimumConfidence
    }

    func extractText(from image: UIImage) async throws -> [RecognizedTextFeature] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations: [VNRecognizedTextObservation] = request.results ?? []

        let textFeatures: [RecognizedTextFeature] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let confidence = Double(candidate.confidence)
                guard confidence >= minimumConfidence else { return nil }

                let text = normalizedText(candidate.string)
                guard !text.isEmpty else { return nil }

                return RecognizedTextFeature(text: text, confidence: confidence)
            }

        let bestByNormalizedText = textFeatures.reduce(into: [String: RecognizedTextFeature]()) {
            (partialResult: inout [String: RecognizedTextFeature], feature: RecognizedTextFeature) in
                let normalized = feature.text.lowercased()
                let current = partialResult[normalized]
                if current == nil || current!.confidence < feature.confidence {
                    partialResult[normalized] = feature
                }
            }

        return bestByNormalizedText.values
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(maxResults)
            .map { $0 }
    }

    private func normalizedText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

}

protocol GeoPointResolving: Sendable {
    func resolveGeoPoint(from recognizedText: [RecognizedTextFeature]) async -> GeoPoint?
}

struct OCRGeoPointResolver: GeoPointResolving {
    func resolveGeoPoint(from recognizedText: [RecognizedTextFeature]) async -> GeoPoint? {
        let candidates = geoCandidates(from: recognizedText.map(\.text))

        for candidate in candidates {
            guard let mapItem = try? await MKGeocodingRequest(addressString: candidate)?.mapItems.first else {
                continue
            }

            return GeoPoint(
                name: canonicalName(for: mapItem, fallback: candidate),
                latitude: mapItem.location.coordinate.latitude,
                longitude: mapItem.location.coordinate.longitude
            )
        }

        return nil
    }

    private func geoCandidates(from strings: [String]) -> [String] {
        var candidates: [String] = []
        let joinedText = strings.joined(separator: "\n")

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let range = NSRange(joinedText.startIndex..<joinedText.endIndex, in: joinedText)
            let matches = detector.matches(in: joinedText, range: range)
            candidates += matches.flatMap { match in
                [
                    match.addressComponents?[.city],
                    match.addressComponents?[.country],
                    match.addressComponents?[.state],
                    match.addressComponents?[.street]
                ].compactMap { $0 }
            }
        }

        candidates += strings.compactMap(cleanGeoCandidate)

        var seen = Set<String>()
        return candidates.compactMap { rawCandidate in
            let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = candidate.lowercased()
            guard !candidate.isEmpty, seen.insert(key).inserted else { return nil }
            return candidate
        }
        .sorted { lhs, rhs in
            let lhsWords = lhs.split(whereSeparator: \.isWhitespace).count
            let rhsWords = rhs.split(whereSeparator: \.isWhitespace).count
            if lhsWords != rhsWords { return lhsWords < rhsWords }
            return lhs.count < rhs.count
        }
    }

    private func cleanGeoCandidate(_ text: String) -> String? {
        let withoutYear = text.replacingOccurrences(
            of: #"(19|20)\d{2}"#,
            with: "",
            options: .regularExpression
        )
        let cleaned = withoutYear
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\S+@\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^[:alpha:]\s\-',.]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        guard cleaned.count >= 3, cleaned.count <= 48 else { return nil }
        guard cleaned.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return nil }
        return cleaned
    }

    private func canonicalName(for mapItem: MKMapItem, fallback: String) -> String {
        let city = mapItem.addressRepresentations?.cityName?.nilIfBlank
        let region = mapItem.addressRepresentations?.cityWithContext(.short)
            .flatMap { normalizedRegion(from: $0, city: city) }
        let country = mapItem.addressRepresentations?.regionName?.nilIfBlank

        if let city, let region, city.caseInsensitiveCompare(region) != ComparisonResult.orderedSame {
            return deduplicatedGeoParts([city, region]).joined(separator: ", ")
        }

        return deduplicatedGeoParts([city, region, country, mapItem.name, fallback])
            .first ?? fallback
    }

    private func normalizedRegion(from cityWithContext: String, city: String?) -> String? {
        let parts = cityWithContext
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let city else { return parts.first?.nilIfBlank }
        return parts.first { $0.caseInsensitiveCompare(city) != .orderedSame }?.nilIfBlank
    }

    private func deduplicatedGeoParts(_ parts: [String?]) -> [String] {
        var seen = Set<String>()
        return parts.compactMap { part in
            guard let value = part?.nilIfBlank else { return nil }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return value
        }
    }
}

struct DefaultPhotoAnalysisService: PhotoAnalysisService {
    private let extractor: any VisionFeatureExtracting
    private let textExtractor: any TextFeatureExtracting
    private let geoResolver: any GeoPointResolving

    init(
        extractor: any VisionFeatureExtracting = VisionFeatureExtractor(),
        textExtractor: any TextFeatureExtracting = VisionTextFeatureExtractor(),
        geoResolver: any GeoPointResolving = OCRGeoPointResolver()
    ) {
        self.extractor = extractor
        self.textExtractor = textExtractor
        self.geoResolver = geoResolver
    }

    func analyze(image: UIImage) async -> PhotoAnalysisResult {
        async let extractedFeatures = try? extractor.extractFeatures(from: image)
        async let extractedText = try? textExtractor.extractText(from: image)

        let features = await extractedFeatures ?? []
        let recognizedText = await extractedText ?? []
        async let resolvedGeo = geoResolver.resolveGeoPoint(from: recognizedText)
        let geo = await resolvedGeo

        return PhotoAnalysisResult(
            tags: allTags(from: features, recognizedText: recognizedText, geo: geo),
            year: extractYear(from: recognizedText),
            geo: geo,
            visionFeatures: features,
            normalizedTags: normalize(features: features),
            recognizedText: recognizedText,
            visualKeywords: extractVisualKeywords(from: features)
        )
    }

    private func allTags(from features: [VisionFeature], recognizedText: [RecognizedTextFeature], geo: GeoPoint?) -> [String] {
        var seen = Set<String>()
        let excludedGeo = geo?.name.lowercased()

        return (visionTags(from: features) + ocrTags(from: recognizedText, excludingGeo: excludedGeo)).compactMap { rawTag in
            let tag = rawTag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag).inserted else { return nil }
            return tag
        }
    }

    private func visionTags(from features: [VisionFeature]) -> [String] {
        var seen = Set<String>()
        return features.compactMap { feature in
            let tag = feature.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag).inserted else { return nil }
            return tag
        }
    }

    private func ocrTags(from recognizedText: [RecognizedTextFeature], excludingGeo geoName: String?) -> [String] {
        recognizedText
            .flatMap { feature in
                feature.text
                    .components(separatedBy: CharacterSet(charactersIn: ",;|/\\()[]{}"))
                    .flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) + [$0] }
            }
            .compactMap { rawTag in
                let tag = rawTag
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                    .lowercased()
                guard tag.count >= 2 else { return nil }
                guard !isYearTag(tag) else { return nil }
                guard geoName.map({ !$0.contains(tag) && !tag.contains($0) }) ?? true else { return nil }
                guard tag.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return nil }
                return tag
            }
    }

    private func isYearTag(_ tag: String) -> Bool {
        guard let year = Int(tag), (1900...2100).contains(year) else { return false }
        return true
    }

    private func normalize(features: [VisionFeature]) -> [NormalizedVisionTag] {
        var bestConfidenceByTag: [PhotoSemanticTag: Double] = [:]

        for feature in features {
            for tag in tags(for: feature.label) {
                bestConfidenceByTag[tag] = max(bestConfidenceByTag[tag] ?? 0, feature.confidence)
            }
        }

        return bestConfidenceByTag
            .map { NormalizedVisionTag(tag: $0.key, confidence: $0.value) }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.tag.rawValue < rhs.tag.rawValue
                }
                return lhs.confidence > rhs.confidence
            }
    }

    private func tags(for label: String) -> Set<PhotoSemanticTag> {
        var result: Set<PhotoSemanticTag> = []
        let normalized = label.lowercased()

        if normalized.contains("bell") || normalized.contains("handbell") || normalized.contains("cowbell") {
            result.insert(.bell)
        }
        if normalized.contains("metal") || normalized.contains("brass") || normalized.contains("bronze") || normalized.contains("copper") {
            result.insert(.metal)
        }
        if normalized.contains("brass") {
            result.insert(.brass)
            result.insert(.shiny)
        }
        if normalized.contains("bronze") || normalized.contains("copper") {
            result.insert(.bronze)
        }
        if normalized.contains("ceramic") || normalized.contains("pottery") {
            result.insert(.ceramic)
        }
        if normalized.contains("porcelain") {
            result.insert(.porcelain)
        }
        if normalized.contains("glass") || normalized.contains("crystal") {
            result.insert(.glass)
            result.insert(.shiny)
        }
        if normalized.contains("wood") || normalized.contains("timber") {
            result.insert(.wood)
        }
        if normalized.contains("silver") || normalized.contains("chrome") || normalized.contains("steel") {
            result.insert(.silver)
            result.insert(.shiny)
        }
        if normalized.contains("stone") || normalized.contains("rock") || normalized.contains("marble") {
            result.insert(.stone)
        }
        if normalized.contains("plastic") || normalized.contains("polymer") || normalized.contains("resin") {
            result.insert(.plastic)
        }
        if normalized.contains("ornament") || normalized.contains("decor") || normalized.contains("decoration") {
            result.insert(.decorative)
        }
        if normalized.contains("antique") || normalized.contains("ancient") {
            result.insert(.antique)
        }
        if normalized.contains("vintage") || normalized.contains("retro") {
            result.insert(.vintage)
        }
        if normalized.contains("rust") || normalized.contains("weathered") || normalized.contains("aged") || normalized.contains("worn") {
            result.insert(.worn)
        }
        if normalized.contains("broken") || normalized.contains("damaged") || normalized.contains("crack") {
            result.insert(.damaged)
        }

        return result
    }

    private func extractYear(from recognizedText: [RecognizedTextFeature]) -> Int? {
        let pattern = #"(19|20)\d{2}"#
        for feature in recognizedText {
            guard let range = feature.text.range(of: pattern, options: .regularExpression),
                  let year = Int(feature.text[range]),
                  (1900...2100).contains(year) else {
                continue
            }
            return year
        }

        return nil
    }

    private func extractVisualKeywords(from features: [VisionFeature]) -> [VisualKeyword] {
        let keywordMap: [(needles: [String], keyword: String)] = [
            (["hedgehog", "porcupine"], "hedgehog"),
            (["owl"], "owl"),
            (["bird"], "bird"),
            (["cat", "kitten", "feline"], "cat"),
            (["dog", "puppy", "canine"], "dog"),
            (["animal", "creature"], "animal"),
            (["figurine", "statuette", "statue", "sculpture"], "figurine"),
            (["ornament", "decor", "decoration"], "decorative"),
            (["toy", "doll"], "toy")
        ]

        var bestByKeyword: [String: Double] = [:]

        for feature in features where feature.confidence >= 0.22 {
            let label = feature.label.lowercased()
            for mapping in keywordMap where mapping.needles.contains(where: label.contains) {
                bestByKeyword[mapping.keyword] = max(bestByKeyword[mapping.keyword] ?? 0, feature.confidence)
            }
        }

        return bestByKeyword
            .map { VisualKeyword(value: $0.key, confidence: $0.value) }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.value < rhs.value
                }
                return lhs.confidence > rhs.confidence
            }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
