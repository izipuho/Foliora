import Foundation
import FoundationModels

/// Represents bibliographic values extracted from book OCR context.
struct BookBibliographicExtraction: Sendable {
    let title: SuggestedFieldValue<String>?
    let authors: [SuggestedFieldValue<String>]
    let publisher: SuggestedFieldValue<String>?
    let publicationYear: SuggestedFieldValue<Int>?
    let languageCode: SuggestedFieldValue<String>?
    let series: SuggestedFieldValue<String>?
    let volumeNumber: SuggestedFieldValue<Int>?

    static let empty = BookBibliographicExtraction(
        title: nil,
        authors: [],
        publisher: nil,
        publicationYear: nil,
        languageCode: nil,
        series: nil,
        volumeNumber: nil
    )
}

/// Defines book-specific bibliographic extraction from generic photo-analysis evidence.
protocol BookBibliographicExtracting: Sendable {
    func extract(from analysis: PhotoAnalysisResult) async -> BookBibliographicExtraction
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@Generable
private struct BookBibliographicGeneratedText {
    @Guide(description: "A bibliographic string copied from the supplied OCR context without translation or transliteration.")
    let value: String

    @Guide(description: "Confidence from 0 to 1.", .range(0.0...1.0))
    let confidence: Double
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@Generable
private struct BookBibliographicGeneratedInteger {
    @Guide(description: "A positive bibliographic integer explicitly supported by the supplied OCR context.")
    let value: Int

    @Guide(description: "Confidence from 0 to 1.", .range(0.0...1.0))
    let confidence: Double
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@Generable
private struct BookBibliographicGeneratedResponse {
    @Guide(description: "The book title only when the supplied OCR context clearly identifies it. Otherwise nil.")
    let title: BookBibliographicGeneratedText?

    @Guide(description: "Author names explicitly supported by the supplied OCR context. One person per element. Return an empty array when no author is supported.")
    let authors: [BookBibliographicGeneratedText]

    @Guide(description: "The publisher name only when the supplied OCR context clearly identifies it. Otherwise nil.")
    let publisher: BookBibliographicGeneratedText?

    @Guide(description: "The publication year only when the supplied OCR context clearly identifies it as a publication or edition year. Otherwise nil.")
    let publicationYear: BookBibliographicGeneratedInteger?

    @Guide(description: "A lowercase ISO 639 language code only when the language is supported by the supplied OCR context. Otherwise nil.")
    let languageCode: BookBibliographicGeneratedText?

    @Guide(description: "The series name only when the supplied OCR context clearly identifies a book series. Otherwise nil.")
    let series: BookBibliographicGeneratedText?

    @Guide(description: "The positive volume number only when the supplied OCR context explicitly identifies a volume, tome, or equivalent series volume. Otherwise nil.")
    let volumeNumber: BookBibliographicGeneratedInteger?
}

/// Extracts book bibliographic metadata from Vision-provided OCR context using Foundation Models.
struct BookBibliographicExtractor: BookBibliographicExtracting {
    func extract(from analysis: PhotoAnalysisResult) async -> BookBibliographicExtraction {
        let recognizedText = analysis.main.recognizedText + analysis.background.recognizedText
        guard !recognizedText.isEmpty else {
            return .empty
        }

        do {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                return .empty
            }

            let session = LanguageModelSession(
                model: model,
                instructions: instructions
            )
            let response = try await session.respond(
                generating: BookBibliographicGeneratedResponse.self,
                options: GenerationOptions(sampling: .greedy)
            ) {
                promptText(
                    mainText: analysis.main.recognizedText,
                    backgroundText: analysis.background.recognizedText
                )
            }

            return extraction(from: response.content)
        } catch {
            return .empty
        }
    }

    private var instructions: String {
        """
        Extract bibliographic metadata for one book using only the supplied OCR context.
        Do not use outside knowledge and do not complete partially visible metadata from memory.
        Return nil or an empty array whenever the supplied OCR does not support a field clearly enough.
        Do not invent genre, page count, condition, tags, notes, acquisition data, origin, identifiers, or any other fields.
        Do not translate or transliterate titles, author names, publisher names, or series names.
        Preserve bibliographic strings in their source form as supported by OCR; do not modernize spelling or silently correct names using outside knowledge.
        Treat a year as publicationYear only when the context supports a publication, printing, copyright, or edition year for this book; ignore unrelated years.
        Treat a number as volumeNumber only when the context explicitly marks it as a volume, tome, book number, or equivalent series volume; never use page count, edition number, price, or identifier digits.
        Return a lowercase ISO 639 language code only when the language is supported by the supplied OCR text; otherwise return nil.
        Separate multiple authors into individual names only when the OCR context supports that separation.
        Every confidence value must be in the range 0...1.
        """
    }

    private func promptText(
        mainText: [RecognizedTextFeature],
        backgroundText: [RecognizedTextFeature]
    ) -> String {
        """
        Analyze these already-collected OCR results from system Vision APIs.
        Do not assume access to the source image and do not perform additional OCR.

        Main-object OCR:
        \(encodedRecognizedText(mainText))

        Background OCR:
        \(encodedRecognizedText(backgroundText))
        """
    }

    private func encodedRecognizedText(_ text: [RecognizedTextFeature]) -> String {
        let promptItems = text.map {
            BookBibliographicPromptText(
                value: $0.text,
                confidence: $0.confidence
            )
        }

        return (try? JSONEncoder().encode(promptItems))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private func extraction(
        from response: BookBibliographicGeneratedResponse
    ) -> BookBibliographicExtraction {
        BookBibliographicExtraction(
            title: suggestedText(from: response.title),
            authors: suggestedAuthors(from: response.authors),
            publisher: suggestedText(from: response.publisher),
            publicationYear: suggestedPositiveInteger(from: response.publicationYear),
            languageCode: suggestedLanguageCode(from: response.languageCode),
            series: suggestedText(from: response.series),
            volumeNumber: suggestedPositiveInteger(from: response.volumeNumber)
        )
    }

    private func suggestedText(
        from generated: BookBibliographicGeneratedText?
    ) -> SuggestedFieldValue<String>? {
        guard let generated else { return nil }

        let value = generated.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        return SuggestedFieldValue(
            value: value,
            confidence: normalizedConfidence(generated.confidence)
        )
    }

    private func suggestedAuthors(
        from generated: [BookBibliographicGeneratedText]
    ) -> [SuggestedFieldValue<String>] {
        var seen: Set<String> = []

        return generated.compactMap { author in
            guard let suggestion = suggestedText(from: author) else { return nil }
            let key = normalizedDeduplicationKey(suggestion.value)
            guard seen.insert(key).inserted else { return nil }
            return suggestion
        }
    }

    private func suggestedPositiveInteger(
        from generated: BookBibliographicGeneratedInteger?
    ) -> SuggestedFieldValue<Int>? {
        guard let generated, generated.value > 0 else { return nil }

        return SuggestedFieldValue(
            value: generated.value,
            confidence: normalizedConfidence(generated.confidence)
        )
    }

    private func suggestedLanguageCode(
        from generated: BookBibliographicGeneratedText?
    ) -> SuggestedFieldValue<String>? {
        guard let generated else { return nil }

        let value = generated.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !value.isEmpty else { return nil }

        let supportedCodes = Set(
            Locale.LanguageCode.isoLanguageCodes.map { $0.identifier.lowercased() }
        )
        guard supportedCodes.contains(value) else { return nil }

        return SuggestedFieldValue(
            value: value,
            confidence: normalizedConfidence(generated.confidence)
        )
    }

    private func normalizedDeduplicationKey(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func normalizedConfidence(_ confidence: Double) -> Double {
        min(max(confidence, 0), 1)
    }
}

private struct BookBibliographicPromptText: Encodable {
    let value: String
    let confidence: Double
}
