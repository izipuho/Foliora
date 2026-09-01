import Foundation

/// Defines deterministic extraction of book identifiers from photo-analysis evidence.
protocol BookIdentifierExtracting: Sendable {
    nonisolated func extract(from analysis: PhotoAnalysisResult) -> [SuggestedFieldValue<BookIdentifier>]
}

/// Extracts and validates ISBN identifiers from barcode and OCR evidence.
struct BookIdentifierExtractor: BookIdentifierExtracting {
    private enum EvidenceSource: Int, Sendable {
        case barcode
        case recognizedText
    }

    private struct Candidate: Sendable {
        let identifier: BookIdentifier
        let confidence: Double
        let source: EvidenceSource
    }

    nonisolated func extract(from analysis: PhotoAnalysisResult) -> [SuggestedFieldValue<BookIdentifier>] {
        var candidates: [Candidate] = []

        let barcodes = analysis.main.recognizedBarcodes + analysis.background.recognizedBarcodes
        for barcode in barcodes {
            if let identifier = identifier(fromExactValue: barcode.payload) {
                candidates.append(
                    Candidate(
                        identifier: identifier,
                        confidence: normalizedConfidence(barcode.confidence),
                        source: .barcode
                    )
                )
            }
        }

        let recognizedText = analysis.main.recognizedText + analysis.background.recognizedText
        for text in recognizedText {
            for identifier in identifiers(in: text.text) {
                candidates.append(
                    Candidate(
                        identifier: identifier,
                        confidence: normalizedConfidence(text.confidence),
                        source: .recognizedText
                    )
                )
            }
        }

        return deduplicated(candidates).map {
            SuggestedFieldValue(value: $0.identifier, confidence: $0.confidence)
        }
    }

    private nonisolated func identifier(fromExactValue rawValue: String) -> BookIdentifier? {
        let normalized = normalizedIdentifier(rawValue)

        if isValidISBN13(normalized) {
            return BookIdentifier(type: .isbn13, value: normalized)
        }
        if isValidISBN10(normalized) {
            return BookIdentifier(type: .isbn10, value: normalized)
        }

        return nil
    }

    private nonisolated func identifiers(in text: String) -> [BookIdentifier] {
        let isbn13Matches = matches(
            pattern: #"(?<![0-9A-Za-z])97[89](?:[\s-]*[0-9]){10}(?![0-9A-Za-z])"#,
            in: text
        )
        let isbn13Ranges = isbn13Matches.map(\.range)

        var identifiers = isbn13Matches.compactMap { match in
            identifier(fromExactValue: match.value)
        }

        let isbn10Matches = matches(
            pattern: #"(?<![0-9A-Za-z])[0-9](?:[\s-]*[0-9]){8}[\s-]*[0-9Xx](?![0-9A-Za-z])"#,
            in: text
        )
        for match in isbn10Matches where !isbn13Ranges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
            if let identifier = identifier(fromExactValue: match.value) {
                identifiers.append(identifier)
            }
        }

        return identifiers
    }

    private nonisolated func matches(pattern: String, in text: String) -> [(value: String, range: NSRange)] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: searchRange).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            return (String(text[range]), match.range)
        }
    }

    private nonisolated func normalizedIdentifier(_ rawValue: String) -> String {
        rawValue
            .filter { !$0.isWhitespace && $0 != "-" }
            .uppercased()
    }

    private nonisolated func isValidISBN10(_ value: String) -> Bool {
        guard value.count == 10 else { return false }

        let characters = Array(value)
        var sum = 0

        for index in 0..<10 {
            let character = characters[index]
            let digit: Int

            if index == 9, character == "X" {
                digit = 10
            } else if let number = character.wholeNumberValue {
                digit = number
            } else {
                return false
            }

            sum += digit * (10 - index)
        }

        return sum.isMultiple(of: 11)
    }

    private nonisolated func isValidISBN13(_ value: String) -> Bool {
        guard value.count == 13,
              value.hasPrefix("978") || value.hasPrefix("979"),
              !value.hasPrefix("9790") else {
            return false
        }

        let digits = value.compactMap(\.wholeNumberValue)
        guard digits.count == 13 else { return false }

        let weightedSum = digits.prefix(12).enumerated().reduce(0) { partialResult, entry in
            let (index, digit) = entry
            return partialResult + digit * (index.isMultiple(of: 2) ? 1 : 3)
        }
        let expectedCheckDigit = (10 - weightedSum % 10) % 10

        return digits[12] == expectedCheckDigit
    }

    private nonisolated func normalizedConfidence(_ confidence: Double) -> Double {
        min(max(confidence, 0), 1)
    }

    private nonisolated func deduplicated(_ candidates: [Candidate]) -> [Candidate] {
        var bestByIdentifier: [BookIdentifier: Candidate] = [:]

        for candidate in candidates {
            guard let current = bestByIdentifier[candidate.identifier] else {
                bestByIdentifier[candidate.identifier] = candidate
                continue
            }

            if candidate.source.rawValue < current.source.rawValue
                || (candidate.source == current.source && candidate.confidence > current.confidence) {
                bestByIdentifier[candidate.identifier] = candidate
            }
        }

        return bestByIdentifier.values.sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return lhs.source.rawValue < rhs.source.rawValue
            }
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            if lhs.identifier.type != rhs.identifier.type {
                return lhs.identifier.type == .isbn13
            }
            return lhs.identifier.value < rhs.identifier.value
        }
    }
}
