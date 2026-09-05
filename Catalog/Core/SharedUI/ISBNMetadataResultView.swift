import Foundation
import SwiftUI

/// Offers an experimental Google Books lookup when a photo suggestion contains a valid ISBN.
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

/// Displays metadata fetched from Google Books for a single ISBN.
struct ISBNMetadataResultView: View {
    let isbn: String

    @Environment(\.dismiss) private var dismiss

    @State private var volume: GoogleBooksVolume?
    @State private var rawResponse: String?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: CatalogMetrics.Spacing.md) {
                        ProgressView()
                        Text("Fetching Google Books data…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let volume {
                    metadataList(volume)
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

    private func metadataList(_ volume: GoogleBooksVolume) -> some View {
        let info = volume.volumeInfo

        return List {
            Section("Lookup") {
                metadataRow("ISBN", isbn)
                metadataRow("Source", "Google Books")
                metadataRow("Volume ID", volume.id)
            }

            if let coverURL = coverURL(from: info.imageLinks) {
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
                metadataRow("Title", info.title)
                metadataRow("Subtitle", info.subtitle)
                metadataRow("Authors", joined(info.authors))
                metadataRow("Publisher", info.publisher)
                metadataRow("Publish date", info.publishedDate)
                metadataRow("Pages", info.pageCount.map(String.init))
                metadataRow("Language", info.language)
                metadataRow("Categories", joined(info.categories))
            }

            if let description = info.description, !description.isEmpty {
                Section("Description") {
                    Text(description)
                        .textSelection(.enabled)
                }
            }

            Section("Identifiers") {
                metadataRow("ISBN-10", identifierValue("ISBN_10", in: info.industryIdentifiers))
                metadataRow("ISBN-13", identifierValue("ISBN_13", in: info.industryIdentifiers))

                ForEach(info.industryIdentifiers ?? [], id: \.displayKey) { identifier in
                    if identifier.type != "ISBN_10", identifier.type != "ISBN_13" {
                        metadataRow(identifier.type, identifier.identifier)
                    }
                }
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

    private func identifierValue(
        _ type: String,
        in identifiers: [GoogleBooksIndustryIdentifier]?
    ) -> String? {
        identifiers?.first(where: { $0.type == type })?.identifier
    }

    private func coverURL(from imageLinks: GoogleBooksImageLinks?) -> URL? {
        guard let source = imageLinks?.bestAvailable,
              var components = URLComponents(string: source) else {
            return nil
        }

        if components.scheme == "http" {
            components.scheme = "https"
        }

        return components.url
    }

    @MainActor
    private func fetchMetadata() async {
        isLoading = true
        volume = nil
        rawResponse = nil
        errorMessage = nil

        do {
            guard let url = googleBooksURL(for: isbn) else {
                throw ISBNMetadataError.invalidURL
            }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ISBNMetadataError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ISBNMetadataError.httpStatus(httpResponse.statusCode)
            }

            let decoded = try JSONDecoder().decode(GoogleBooksSearchResponse.self, from: data)
            guard let match = bestMatch(for: isbn, in: decoded.items) else {
                throw ISBNMetadataError.notFound
            }

            volume = match
            rawResponse = prettyPrintedJSON(from: data)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func bestMatch(
        for isbn: String,
        in volumes: [GoogleBooksVolume]?
    ) -> GoogleBooksVolume? {
        guard let volumes, !volumes.isEmpty else { return nil }

        if let exactMatch = volumes.first(where: { volume in
            volume.volumeInfo.industryIdentifiers?
                .contains(where: { normalizeISBN($0.identifier) == isbn }) == true
        }) {
            return exactMatch
        }

        return volumes.first
    }

    private func normalizeISBN(_ value: String) -> String {
        value
            .filter { $0.isNumber || $0 == "X" || $0 == "x" }
            .uppercased()
    }

    private func googleBooksURL(for isbn: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = "/books/v1/volumes"
        components.queryItems = [
            URLQueryItem(name: "q", value: "isbn:\(isbn)"),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "projection", value: "full")
        ]
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

private struct GoogleBooksSearchResponse: Decodable {
    let totalItems: Int?
    let items: [GoogleBooksVolume]?
}

private struct GoogleBooksVolume: Decodable {
    let id: String
    let volumeInfo: GoogleBooksVolumeInfo
}

private struct GoogleBooksVolumeInfo: Decodable {
    let title: String?
    let subtitle: String?
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?
    let description: String?
    let industryIdentifiers: [GoogleBooksIndustryIdentifier]?
    let pageCount: Int?
    let categories: [String]?
    let imageLinks: GoogleBooksImageLinks?
    let language: String?
    let previewLink: String?
    let infoLink: String?
}

private struct GoogleBooksIndustryIdentifier: Decodable {
    let type: String
    let identifier: String

    var displayKey: String {
        "\(type):\(identifier)"
    }
}

private struct GoogleBooksImageLinks: Decodable {
    let smallThumbnail: String?
    let thumbnail: String?
    let small: String?
    let medium: String?
    let large: String?
    let extraLarge: String?

    var bestAvailable: String? {
        extraLarge ?? large ?? medium ?? small ?? thumbnail ?? smallThumbnail
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
            return "Could not create the Google Books request URL."
        case .invalidResponse:
            return "Google Books returned an invalid response."
        case .notFound:
            return "Google Books has no volume for this ISBN."
        case .httpStatus(let statusCode):
            return "Google Books returned HTTP \(statusCode)."
        }
    }
}
