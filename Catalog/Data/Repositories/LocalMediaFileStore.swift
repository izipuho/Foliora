import Core
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct LocalMediaFileStore: Sendable {
    static let shared = LocalMediaFileStore()

    private static let photoThumbnailMaxPixelSize = 1_400

    private let baseURL: URL
    private var thumbnailsURL: URL {
        baseURL.appendingPathComponent("Thumbnails", isDirectory: true)
    }

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
        try? createPhotoThumbnail(from: fileURL, identifier: fileName)
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
        let safeBaseName = FileNameSanitizer.safeBaseName(baseName.isEmpty ? "document" : baseName)
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

    func thumbnailFileURL(for identifier: String) -> URL? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let url = thumbnailsURL.appendingPathComponent(thumbnailFileName(for: trimmed))
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
        try? createPhotoThumbnail(from: destinationURL, identifier: trimmed)
    }

    func deleteFile(for identifier: String) {
        if let url = fileURL(for: identifier) {
            try? FileManager.default.removeItem(at: url)
        }
        if let thumbnailURL = thumbnailFileURL(for: identifier) {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    private func createPhotoThumbnail(from sourceURL: URL, identifier: String) throws {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, sourceOptions) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.photoThumbnailMaxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)

        let destinationURL = thumbnailsURL.appendingPathComponent(thumbnailFileName(for: identifier))
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func thumbnailFileName(for identifier: String) -> String {
        "\(identifier).jpg"
    }

    private func sanitizedFileExtension(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

}
