import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

struct DataSetPreparationView: View {
    @State private var isImporterPresented = false
    @State private var selectedImageURLs: [URL] = []
    @State private var currentImageIndex: Int = 0
    @State private var image: NSImage?
    @State private var mainObjectImage: NSImage?
    @State private var resultBlocks: [DebugResultBlock] = []
    @State private var tagAnnotations: [DatasetTagAnnotation] = []
    @State private var annotationCache: [URL: [DatasetTagAnnotation]] = [:]
    @State private var cropImageCache: [URL: NSImage] = [:]
    @State private var exportMessage: String?

    private var exportableAnnotations: [DatasetTagAnnotation] {
        tagAnnotations.filter { $0.decision.exportValue != nil }
    }

    private var hasExportableCachedAnnotations: Bool {
        annotationCache.values.contains { annotations in
            annotations.contains { $0.decision.exportValue != nil }
        } || !exportableAnnotations.isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Button("Select Images") {
                isImporterPresented = true
            }
                .buttonStyle(.borderedProminent)

            if !selectedImageURLs.isEmpty {
                HStack(spacing: 12) {
                    Button("Previous") {
                        Task {
                            await selectImage(at: currentImageIndex - 1)
                        }
                    }
                    .disabled(currentImageIndex <= 0)

                    Text("\(currentImageIndex + 1) / \(selectedImageURLs.count)")
                        .monospacedDigit()

                    Button("Next") {
                        Task {
                            await selectImage(at: currentImageIndex + 1)
                        }
                    }
                    .disabled(currentImageIndex >= selectedImageURLs.count - 1)
                }
            }

            if image != nil {
                HStack(spacing: 12) {
                    Button("Save To Dataset") {
                        saveCurrentAnnotationToDataset()
                    }
                    .disabled(exportableAnnotations.isEmpty)

                    Button("Save All Annotated") {
                        saveAllAnnotatedToDataset()
                    }
                    .disabled(!hasExportableCachedAnnotations)

                    if let exportMessage {
                        Text(exportMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let image {
                HStack(alignment: .top, spacing: 12) {
                    DebugImagePreview(title: "before", image: image)

                    if let mainObjectImage {
                        DebugImagePreview(title: "after", image: mainObjectImage)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !tagAnnotations.isEmpty {
                        DatasetTagAnnotationBlock(annotations: $tagAnnotations)
                    }

                    ForEach(resultBlocks) { block in
                        DebugResultBlockView(block: block)
                    }
                }
            }
        }
        .padding()
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                selectedImageURLs = urls
                currentImageIndex = 0
                annotationCache = [:]
                cropImageCache = [:]
                Task {
                    await loadImage(at: currentImageIndex)
                }
            }
        }
    }

    private func selectImage(at index: Int) async {
        persistCurrentAnnotationState()
        currentImageIndex = index
        await loadImage(at: index)
    }

    private func loadImage(at index: Int) async {
        guard selectedImageURLs.indices.contains(index) else { return }

        let url = selectedImageURLs[index]
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        image = nsImage
        mainObjectImage = nil
        resultBlocks = []
        tagAnnotations = annotationCache[url] ?? []
        exportMessage = nil

        await analyze(cgImage: cgImage)
    }

    private func analyze(cgImage: CGImage) async {
        let service = DefaultPhotoAnalysisService()

        let analysis: PhotoAnalysisResult = await service.analyze(image: cgImage)
        mainObjectImage = analysis.mainObjectImage.map {
            NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
        }
        if selectedImageURLs.indices.contains(currentImageIndex) {
            let currentURL = selectedImageURLs[currentImageIndex]
            cropImageCache[currentURL] = mainObjectImage ?? image
            if let cachedAnnotations = annotationCache[currentURL] {
                tagAnnotations = cachedAnnotations
            } else {
                tagAnnotations = analysis.main.allTags.map {
                    DatasetTagAnnotation(label: $0.label, confidence: $0.confidence)
                }
            }
        }

        let filteredVision = analysis.main.allTags
            .filter { $0.confidence > 0.5 }
            .map { "\($0.label) (\($0.confidence))" }
            .joined(separator: "\n")
        
        resultBlocks = [
            DebugResultBlock(title: "Filtered features", text: filteredVision),
        ]
    }

    private func saveCurrentAnnotationToDataset() {
        persistCurrentAnnotationState()

        guard selectedImageURLs.indices.contains(currentImageIndex),
              let outputRootURL = chooseDatasetRootDirectory() else { return }

        do {
            let result = try withSecurityScopedAccess(to: outputRootURL) {
                let datasetDirectory = try createDatasetDirectory(in: outputRootURL)
                let savedRecords = try exportAnnotations(for: selectedImageURLs[currentImageIndex], to: datasetDirectory)
                return (savedRecords, datasetDirectory.annotationsURL)
            }
            exportMessage = "Saved \(result.0) tags to \(result.1.path)"
        } catch {
            exportMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveAllAnnotatedToDataset() {
        persistCurrentAnnotationState()

        guard let outputRootURL = chooseDatasetRootDirectory() else { return }

        do {
            let result = try withSecurityScopedAccess(to: outputRootURL) {
                let datasetDirectory = try createDatasetDirectory(in: outputRootURL)
                var savedRecords = 0
                for url in selectedImageURLs {
                    savedRecords += try exportAnnotations(for: url, to: datasetDirectory)
                }
                return (savedRecords, datasetDirectory.annotationsURL)
            }
            exportMessage = "Saved \(result.0) tags to \(result.1.path)"
        } catch {
            exportMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func persistCurrentAnnotationState() {
        guard selectedImageURLs.indices.contains(currentImageIndex) else { return }

        let currentURL = selectedImageURLs[currentImageIndex]
        annotationCache[currentURL] = tagAnnotations
        if let cropSourceImage = mainObjectImage ?? image {
            cropImageCache[currentURL] = cropSourceImage
        }
    }

    private func exportAnnotations(for sourceURL: URL, to datasetDirectory: DatasetDirectory) throws -> Int {
        guard let cropSourceImage = cropImageCache[sourceURL] else { return 0 }

        let exportableAnnotations = (annotationCache[sourceURL] ?? [])
            .filter { $0.decision.exportValue != nil }
        guard !exportableAnnotations.isEmpty else { return 0 }

        let photoID = sourceURL.deletingPathExtension().lastPathComponent
        let cropFileName = try saveCropImage(cropSourceImage, photoID: photoID, cropsURL: datasetDirectory.cropsURL)
        let records = exportableAnnotations.compactMap { annotation -> DatasetExportRecord? in
            guard let decision = annotation.decision.exportValue else { return nil }

            return DatasetExportRecord(
                photoID: photoID,
                cropFileName: cropFileName,
                tag: annotation.label,
                confidence: annotation.confidence,
                decision: decision
            )
        }
        try appendJSONLLines(records, to: datasetDirectory.annotationsURL)

        return records.count
    }

    private func withSecurityScopedAccess<T>(to url: URL, perform work: () throws -> T) rethrows -> T {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try work()
    }

    private func chooseDatasetRootDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Save To Dataset"
        panel.prompt = "Save"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedImageURLs.indices.contains(currentImageIndex)
            ? selectedImageURLs[currentImageIndex].deletingLastPathComponent()
            : nil

        return panel.runModal() == .OK ? panel.url : nil
    }

    private func createDatasetDirectory(in outputRootURL: URL) throws -> DatasetDirectory {
        let datasetURL = outputRootURL.appendingPathComponent("dataset", isDirectory: true)
        let cropsURL = datasetURL.appendingPathComponent("crops", isDirectory: true)
        try FileManager.default.createDirectory(at: cropsURL, withIntermediateDirectories: true)

        return DatasetDirectory(
            cropsURL: cropsURL,
            annotationsURL: datasetURL.appendingPathComponent("annotations.jsonl")
        )
    }

    private func saveCropImage(_ cropImage: NSImage, photoID: String, cropsURL: URL) throws -> String {
        guard let cgImage = cropImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DatasetExportError.invalidImage
        }

        let fileName = "\(photoID)-\(UUID().uuidString).jpg"
        let outputURL = cropsURL.appendingPathComponent(fileName)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw DatasetExportError.invalidImage
        }

        try data.write(to: outputURL, options: .atomic)
        return fileName
    }

    private func appendJSONLLines(_ records: [DatasetExportRecord], to annotationsURL: URL) throws {
        let encoder = JSONEncoder()
        var lines = ""
        for record in records {
            let data = try encoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else {
                throw DatasetExportError.invalidJSON
            }
            lines += line + "\n"
        }

        guard let data = lines.data(using: .utf8) else {
            throw DatasetExportError.invalidJSON
        }

        if FileManager.default.fileExists(atPath: annotationsURL.path) {
            let handle = try FileHandle(forWritingTo: annotationsURL)
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
        } else {
            try data.write(to: annotationsURL, options: .atomic)
        }
    }
}

private enum DatasetTagDecision {
    case undecided
    case keep
    case rejectNoise
    case rejectWrong
}

private extension DatasetTagDecision {
    var exportValue: String? {
        switch self {
        case .undecided:
            nil
        case .keep:
            "keep"
        case .rejectNoise:
            "rejectNoise"
        case .rejectWrong:
            "rejectWrong"
        }
    }
}

private struct DatasetTagAnnotation: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Double
    var decision: DatasetTagDecision = .undecided
}

private struct DebugResultBlock: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

private struct DatasetExportRecord: Codable {
    let photoID: String
    let cropFileName: String
    let tag: String
    let confidence: Double
    let decision: String
}

private struct DatasetDirectory {
    let cropsURL: URL
    let annotationsURL: URL
}

private enum DatasetExportError: LocalizedError {
    case invalidImage
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "Could not encode image"
        case .invalidJSON:
            "Could not encode annotation JSON"
        }
    }
}

private struct DebugImagePreview: View {
    let title: String
    let image: NSImage

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 200)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DatasetTagAnnotationBlock: View {
    @Binding var annotations: [DatasetTagAnnotation]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tag annotation")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach($annotations) { $annotation in
                    HStack(spacing: 12) {
                        Text(annotation.label)
                            .frame(width: 180, alignment: .leading)
                            .lineLimit(1)

                        Text(annotation.confidence, format: .number.precision(.fractionLength(3)))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)

                        DatasetTagDecisionButton(title: "Keep", isSelected: annotation.decision == .keep) {
                            annotation.decision = .keep
                        }

                        DatasetTagDecisionButton(title: "Noise", isSelected: annotation.decision == .rejectNoise) {
                            annotation.decision = .rejectNoise
                        }

                        DatasetTagDecisionButton(title: "Wrong", isSelected: annotation.decision == .rejectWrong) {
                            annotation.decision = .rejectWrong
                        }

                        DatasetTagDecisionButton(title: "Undecided", isSelected: annotation.decision == .undecided) {
                            annotation.decision = .undecided
                        }
                    }
                    .padding(8)
                    .background(decisionColor(annotation.decision))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 520, alignment: .leading)
        }
    }

    private func decisionColor(_ decision: DatasetTagDecision) -> Color {
        switch decision {
        case .undecided:
            Color(nsColor: .windowBackgroundColor)
        case .keep:
            Color.green.opacity(0.16)
        case .rejectNoise:
            Color.orange.opacity(0.18)
        case .rejectWrong:
            Color.red.opacity(0.16)
        }
    }
}

private struct DatasetTagDecisionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isSelected ? .accentColor : nil)
    }
}

private struct DebugResultBlockView: View {
    let block: DebugResultBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.title)
                .font(.headline)

            ZStack(alignment: .topTrailing) {
                Text(block.text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(block.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .padding(8)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
