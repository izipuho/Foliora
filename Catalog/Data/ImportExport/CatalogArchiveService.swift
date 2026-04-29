import Foundation

struct CatalogArchiveService: Sendable {
    enum ArchiveError: LocalizedError {
        case corruptArchive
        case missingCatalogJSON
        case unsupportedCompression
        case unsafeArchivePath

        var errorDescription: String? {
            switch self {
            case .corruptArchive:
                String(localized: "settings.import.error.corrupt_archive")
            case .missingCatalogJSON:
                String(localized: "settings.import.error.missing_catalog_json")
            case .unsupportedCompression:
                String(localized: "settings.import.error.unsupported_archive")
            case .unsafeArchivePath:
                String(localized: "settings.import.error.corrupt_archive")
            }
        }
    }

    func createArchive(from sourceDirectory: URL, to destinationURL: URL) throws {
        let entries = try archivedFiles(in: sourceDirectory)
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            let fileData = try Data(contentsOf: entry.url)
            let nameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(fileData)
            let localHeaderOffset = UInt32(output.count)

            output.appendUInt32(0x04034b50)
            output.appendUInt16(20)
            output.appendUInt16(0x0800)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt32(crc)
            output.appendUInt32(UInt32(fileData.count))
            output.appendUInt32(UInt32(fileData.count))
            output.appendUInt16(UInt16(nameData.count))
            output.appendUInt16(0)
            output.append(nameData)
            output.append(fileData)

            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0x0800)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(UInt32(fileData.count))
            centralDirectory.appendUInt32(UInt32(fileData.count))
            centralDirectory.appendUInt16(UInt16(nameData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(localHeaderOffset)
            centralDirectory.append(nameData)
        }

        let centralDirectoryOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendUInt32(0x06054b50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(UInt32(centralDirectory.count))
        output.appendUInt32(centralDirectoryOffset)
        output.appendUInt16(0)

        try output.write(to: destinationURL, options: .atomic)
    }

    func extractArchive(at archiveURL: URL, to destinationDirectory: URL) throws {
        let archiveData = try Data(contentsOf: archiveURL)
        guard let endOfCentralDirectory = archiveData.endOfCentralDirectoryOffset else {
            throw ArchiveError.corruptArchive
        }

        let entryCount = Int(try archiveData.uint16(at: endOfCentralDirectory + 10))
        let centralDirectoryOffset = Int(try archiveData.uint32(at: endOfCentralDirectory + 16))
        var cursor = centralDirectoryOffset

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        for _ in 0..<entryCount {
            guard try archiveData.uint32(at: cursor) == 0x02014b50 else {
                throw ArchiveError.corruptArchive
            }

            let compressionMethod = try archiveData.uint16(at: cursor + 10)
            let expectedCRC = try archiveData.uint32(at: cursor + 16)
            let compressedSize = Int(try archiveData.uint32(at: cursor + 20))
            let uncompressedSize = Int(try archiveData.uint32(at: cursor + 24))
            let fileNameLength = Int(try archiveData.uint16(at: cursor + 28))
            let extraLength = Int(try archiveData.uint16(at: cursor + 30))
            let commentLength = Int(try archiveData.uint16(at: cursor + 32))
            let localHeaderOffset = Int(try archiveData.uint32(at: cursor + 42))
            let fileNameStart = cursor + 46
            let fileNameEnd = fileNameStart + fileNameLength

            guard fileNameEnd <= archiveData.count,
                  let path = String(data: archiveData[fileNameStart..<fileNameEnd], encoding: .utf8)
            else {
                throw ArchiveError.corruptArchive
            }

            cursor = fileNameEnd + extraLength + commentLength

            guard !path.hasSuffix("/") else { continue }
            guard compressionMethod == 0 else { throw ArchiveError.unsupportedCompression }
            guard compressedSize == uncompressedSize else { throw ArchiveError.corruptArchive }
            guard try archiveData.uint32(at: localHeaderOffset) == 0x04034b50 else {
                throw ArchiveError.corruptArchive
            }

            let localNameLength = Int(try archiveData.uint16(at: localHeaderOffset + 26))
            let localExtraLength = Int(try archiveData.uint16(at: localHeaderOffset + 28))
            let fileDataStart = localHeaderOffset + 30 + localNameLength + localExtraLength
            let fileDataEnd = fileDataStart + compressedSize
            guard fileDataEnd <= archiveData.count else { throw ArchiveError.corruptArchive }

            let fileData = archiveData[fileDataStart..<fileDataEnd]
            guard CRC32.checksum(Data(fileData)) == expectedCRC else { throw ArchiveError.corruptArchive }

            let destinationURL = try safeDestinationURL(for: path, in: destinationDirectory)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(fileData).write(to: destinationURL, options: .atomic)
        }
    }

    private func archivedFiles(in directoryURL: URL) throws -> [(path: String, url: URL)] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(path: String, url: URL)] = []
        let basePath = directoryURL.standardizedFileURL.path

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            var relativePath = fileURL.standardizedFileURL.path
            guard relativePath.hasPrefix(basePath) else { continue }
            relativePath.removeFirst(basePath.count)
            relativePath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            files.append((relativePath, fileURL))
        }

        return files.sorted { $0.path < $1.path }
    }

    private func safeDestinationURL(for path: String, in directoryURL: URL) throws -> URL {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw ArchiveError.unsafeArchivePath
        }

        return components.reduce(directoryURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0...255).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    var endOfCentralDirectoryOffset: Int? {
        guard count >= 22 else { return nil }
        let lowerBound = Swift.max(0, count - 65_557)
        var offset = count - 22

        while offset >= lowerBound {
            if (try? uint32(at: offset)) == 0x06054b50 {
                return offset
            }
            offset -= 1
        }

        return nil
    }

    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw CatalogArchiveService.ArchiveError.corruptArchive }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw CatalogArchiveService.ArchiveError.corruptArchive }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
