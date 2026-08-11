import Foundation
import Translation

/// Defines the supported translation availability values.
public enum TranslationAvailability: Sendable {
    case available
    case supportedButNotInstalled
    case unsupported
}

/// Defines the supported translation preparation state values.
public enum TranslationPreparationState: Sendable, Equatable {
    case notRequired
    case ready
    case needsDownload
    case unsupported
}

/// Represents text translator data and behavior.
public struct TextTranslator: Sendable {
    /// Language expected in the source text.
    public let sourceLanguage: Locale.Language

    /// Creates a translator for the supplied source language.
    public init(
        sourceLanguage: Locale.Language = Locale.Language(identifier: "en")
    ) {
        self.sourceLanguage = sourceLanguage
    }

    /// Returns the user's preferred translation target language.
    public func targetLanguage() -> Locale.Language {
        guard let preferredLanguage = Locale.preferredLanguages.first else {
            return Locale.Language(identifier: "en")
        }

        let language = Locale.Language(identifier: preferredLanguage)
        return language.languageCode == nil ? Locale.Language(identifier: "en") : language
    }

    /// Reports whether translation is ready or requires preparation.
    public func preparationState() async -> TranslationPreparationState {
        let targetLanguage = targetLanguage()

        if sourceLanguage.isEquivalent(to: targetLanguage) {
            return .notRequired
        }

        switch await availability(from: sourceLanguage, to: targetLanguage) {
        case .available:
            return .ready
        case .supportedButNotInstalled:
            return .needsDownload
        case .unsupported:
            return .unsupported
        }
    }

    /// Checks translation support for a language pair.
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

    /// Translates texts while preserving their original order.
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
