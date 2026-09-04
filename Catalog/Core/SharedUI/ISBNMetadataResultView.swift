import Foundation
import SwiftUI

/// Offers an experimental Open Library lookup when a photo suggestion contains a valid ISBN.
struct ISBNMetadataFetchButton: View {
    let sourceText: String

    @State private var isPresentingResult = false

    var body: some View {
        if let isbn = ISBNParser.firstValidISBN(in: sourceText) {
            Button("Fetch Data") {
                isPresentingResult = true
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $isPresentingResult) {
                ISBNMetadataResultView(isbn: isbn)
            }
        }
    }
}

/// Displays metadata fetched from Open Library for a single ISBN.
struct ISBNMetadataResultView: View {
    let isbn: String

    @Environment(\.dismiss) private var dismiss

    @State private var edition: OpenLibraryEdition?
    @State private var authorNames: [String] = []
    @State private var rawResponse: String?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: CatalogMetrics.Spacing.md) {
                        ProgressView()
                        Text("Fetching Open Library data…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let edition {
                    metadataList(edition)
                } else {
                    ContentUnavailableView(
                        "Unable to Fetch Data",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage ?? "Unknown error")
                    )
                }
            }
            .navigationTitle("ISBN Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task(id: isbn) {
                await fetchMetadata()
            }
        }
    }

    private func metadataList(_ edition: OpenLibraryEdition) -> some View {
        List {
            Section("Lookup") {
                metadataRow("ISBN", isbn)
                metadataRow("Source", "Open Library")
                metadataRow("Edition key", edition.key)
            }

            if let coverURL = coverURL(for: edition) {
                Section("Cover") {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 320)
                        case .failure:
                            ContentUnavailableView(
                                "Cover Unavailable",
                                systemImage: "book.closed"
                            )
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }

            Section("Metadata") {
                metadataRow("Title", edition.title)
                metadataRow("Subtitle", edition.subtitle)
                metadataRow("Authors", joined(authorNames))
                metadataRow("Publishers", joined(edition.publishers))
                metadataRow("Publish date", edition.publishDate)
                metadataRow("Pages", edition.numberOfPages.map(String.init))
                metadataRow("Languages", languageCodes(from: edition.languages))
                metadataRow("Series", joined(edition.series))
                metadataRow("Contributions", joined(edition.contributions))
                metadataRow("Publish places", joined(edition.publishPlaces))
                metadataRow("Subjects", joined(edition.subjects))
            }

            Section("Identifiers") {
                metadataRow("ISBN-10", joined(edition.isbn10))
                metadataRow("ISBN-13", joined(edition.isbn13))
            }

            if let rawResponse {
                Section {
                    DisclosureGroup("Raw response") {
                        Text(rawResponse)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metadataRow(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    private func joined(_ values: [String]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return values.joined(separator: ", ")
    }

    private func languageCodes(from references: [OpenLibraryReference]?) -> String? {
        guard let references, !references.isEmpty else { return nil }
        let values = references.compactMap { $0.key.split(separator: "/").last.map(String.init) }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    private func coverURL(for edition: OpenLibraryEdition) -> URL? {
        guard let coverID = edition.covers?.first(where: { $0 > 0 }) else { return nil }
        return URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg")
    }

    @MainActor
    private func fetchMetadata() async {
        isLoading = true
        edition = nil
        authorNames = []
        rawResponse = nil
        errorMessage = nil

        do {
            guard let url = openLibraryURL(path: "/isbn/\(isbn).json") else {
                throw ISBNMetadataError.invalidURL
            }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ISBNMetadataError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 404:
                throw ISBNMetadataError.notFound
            default:
                throw ISBNMetadataError.httpStatus(httpResponse.statusCode)
            }

            let decoded = try JSONDecoder().decode(OpenLibraryEdition.self, from: data)
            let names = await fetchAuthorNames(decoded.authors ?? [])

            edition = decoded
            authorNames = names
            rawResponse = prettyPrintedJSON(from: data)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchAuthorNames(_ references: [OpenLibraryReference]) async -> [String] {
        var names: [String] = []

        for reference in references {
            guard let url = openLibraryURL(path: "\(reference.key).json") else { continue }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let author = try? JSONDecoder().decode(OpenLibraryAuthor.self, from: data),
                      let name = author.name,
                      !name.isEmpty else {
                    continue
                }
                names.append(name)
            } catch {
                continue
            }
        }

        return names
    }

    private func openLibraryURL(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openlibrary.org"
        components.path = path
        return components.url
    }

    private func prettyPrintedJSON(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ) else {
            return nil
        }
        return String(data: prettyData, encoding: .utf8)
    }
}

private enum ISBNParser {
    static func firstValidISBN(in sourceText: String) -> String? {
        for line in sourceText.split(separator: "\n") {
            let valuePart: Substring
            if let separator = line.firstIndex(of: ":") {
                valuePart = line[line.index(after: separator)...]
            } else {
                valuePart = line[...]
            }

            let candidate = valuePart
                .filter { $0.isNumber || $0 == "X" || $0 == "x" }
                .uppercased()

            if isValidISBN13(candidate) || isValidISBN10(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func isValidISBN13(_ value: String) -> Bool {
        guard value.count == 13 else { return false }
        let digits = value.compactMap(\.wholeNumberValue)
        guard digits.count == 13 else { return false }

        let sum = digits.prefix(12).enumerated().reduce(0) { partialResult, element in
            let (index, digit) = element
            return partialResult + digit * (index.isMultiple(of: 2) ? 1 : 3)
        }
        let expectedCheckDigit = (10 - (sum % 10)) % 10
        return digits[12] == expectedCheckDigit
    }

    private static func isValidISBN10(_ value: String) -> Bool {
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
}

private struct OpenLibraryReference: Decodable {
    let key: String
}

private struct OpenLibraryAuthor: Decodable {
    let name: String?
}

private struct OpenLibraryEdition: Decodable {
    let key: String?
    let title: String?
    let subtitle: String?
    let authors: [OpenLibraryReference]?
    let publishers: [String]?
    let publishDate: String?
    let numberOfPages: Int?
    let isbn10: [String]?
    let isbn13: [String]?
    let languages: [OpenLibraryReference]?
    let subjects: [String]?
    let covers: [Int]?
    let series: [String]?
    let contributions: [String]?
    let publishPlaces: [String]?

    enum CodingKeys: String, CodingKey {
        case key
        case title
        case subtitle
        case authors
        case publishers
        case languages
        case subjects
        case covers
        case series
        case contributions
        case publishDate = "publish_date"
        case numberOfPages = "number_of_pages"
        case isbn10 = "isbn_10"
        case isbn13 = "isbn_13"
        case publishPlaces = "publish_places"
    }
}

private enum ISBNMetadataError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notFound
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not create the Open Library request URL."
        case .invalidResponse:
            return "Open Library returned an invalid response."
        case .notFound:
            return "Open Library has no edition for this ISBN."
        case .httpStatus(let statusCode):
            return "Open Library returned HTTP \(statusCode)."
        }
    }
}
