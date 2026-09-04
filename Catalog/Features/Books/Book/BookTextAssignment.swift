import Foundation

/// Identifies book editor fields that can receive recognized text.
enum BookTextField: Hashable {
    case title
    case subtitle
    case publicationYear
    case publisher
    case series
    case volume
}

/// Identifies any book editor target that owns assigned text fragments.
enum BookTextTarget: Hashable {
    case field(BookTextField)
    case author(Int)
}

struct BookTextAssignment {
    let text: String
    let confidence: Double
}

enum BookReferenceResolutionStatus {
    case existing
    case new

    var systemImage: String {
        switch self {
        case .existing: "checkmark.circle.fill"
        case .new: "plus.circle"
        }
    }
}

enum BookTextAssignmentRules {
    static func makeAssignment(from fragments: [TextFragment]) -> BookTextAssignment {
        BookTextAssignment(
            text: fragments.map(\.text).joined(separator: " "),
            confidence: fragments.map(\.confidence).min() ?? 0
        )
    }

    static func volumeExtraction(in text: String) -> (range: Range<String.Index>, replacementText: String)? {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression),
              let number = Int(text[range]),
              number > 0 else { return nil }

        return (range, String(number))
    }

    static func publicationYearExtraction(in text: String) -> (range: Range<String.Index>, replacementText: String)? {
        let currentYear = Calendar.current.component(.year, from: .now)
        guard let range = text.range(of: #"\b\d{4}\b"#, options: .regularExpression),
              let year = Int(text[range]),
              (1000...currentYear).contains(year) else { return nil }

        return (range, String(year))
    }

    static func firstPositiveInteger(in value: String) -> Int? {
        value
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int(String($0)) }
            .first(where: { $0 > 0 })
    }
}
