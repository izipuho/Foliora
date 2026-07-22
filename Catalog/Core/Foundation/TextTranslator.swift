import Foundation
import Translation

public enum TranslationAvailability: Sendable {
    case available
    case supportedButNotInstalled
    case unsupported
}

public actor TextTranslator {
    public init() {}

    public func availability(
        from source: Locale.Language,
        to target: Locale.Language
    ) async -> TranslationAvailability {
        guard source != target else {
            return .available
        }

        let availability = LanguageAvailability()

        switch await availability.status(from: source, to: target) {
        case .installed:
            return .available
        case .supported:
            return .supportedButNotInstalled
        case .unsupported:
            return .unsupported
        @unknown default:
            return .unsupported
        }
    }

    public func translate(
        _ texts: [String],
        using session: TranslationSession
    ) async -> [String] {
        guard !texts.isEmpty else { return [] }

        do {
            let requests = texts.enumerated().map { index, text in
                TranslationSession.Request(
                    sourceText: text,
                    clientIdentifier: String(index)
                )
            }
            let responses = try await session.translations(from: requests)
            var translatedTexts = Array<String?>(repeating: nil, count: texts.count)

            for response in responses {
                guard
                    let clientIdentifier = response.clientIdentifier,
                    let index = Int(clientIdentifier),
                    texts.indices.contains(index)
                else {
                    return texts
                }

                translatedTexts[index] = response.targetText
            }

            return translatedTexts.enumerated().map { index, translatedText in
                translatedText ?? texts[index]
            }
        } catch {
            return texts
        }
    }
}
