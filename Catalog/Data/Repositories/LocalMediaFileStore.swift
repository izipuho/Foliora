import Foundation

struct LocalMediaFileStore: Sendable {
    static let shared = LocalMediaFileStore()

    private let baseURL: URL

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catalog", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }

    func savePhoto(data: Data, preferredFileExtension: String?) throws -> String {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let fileExtension = sanitizedFileExtension(preferredFileExtension) ?? "jpg"
        let fileName = "photo-\(UUID().uuidString).\(fileExtension)"
        let fileURL = baseURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    func importDocument(from sourceURL: URL) throws -> String {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeBaseName = sanitizedBaseName(baseName.isEmpty ? "document" : baseName)
        let fileName = ext.isEmpty
            ? "\(safeBaseName)-\(UUID().uuidString)"
            : "\(safeBaseName)-\(UUID().uuidString).\(ext)"

        let destinationURL = baseURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return fileName
    }

    func fileURL(for identifier: String) -> URL? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let url = baseURL.appendingPathComponent(trimmed)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func exportFileURL(for identifier: String) -> URL? {
        fileURL(for: identifier)
    }

    func restoreFile(from sourceURL: URL, identifier: String) throws {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == URL(fileURLWithPath: trimmed).lastPathComponent else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let destinationURL = baseURL.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    func deleteFile(for identifier: String) {
        guard let url = fileURL(for: identifier) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func sanitizedFileExtension(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func sanitizedBaseName(_ value: String) -> String {
        let cleaned = value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return cleaned.isEmpty ? "file" : cleaned
    }
}
