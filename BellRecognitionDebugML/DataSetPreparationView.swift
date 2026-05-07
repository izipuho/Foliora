import SwiftUI
import PhotosUI
import AppKit

struct DataSetPreparationView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: NSImage?
    @State private var mainObjectImage: NSImage?
    @State private var resultBlocks: [DebugResultBlock] = []

    var body: some View {
        VStack(spacing: 20) {
            PhotosPicker("Pick Photo", selection: $selectedItem, matching: .images)
                .buttonStyle(.borderedProminent)

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
                    ForEach(resultBlocks) { block in
                        DebugResultBlockView(block: block)
                    }
                }
            }
        }
        .padding()
        .onChange(of: selectedItem) {
            Task {
                if let data = try? await selectedItem?.loadTransferable(type: Data.self),
                   let nsImage = NSImage(data: data) {
                    image = nsImage
                    mainObjectImage = nil
                    await analyze()
                }
            }
        }
    }

    private func analyze() async {
        guard let image else { return }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let service = DefaultPhotoAnalysisService()
        let semanticExtractor = SemanticPhotoFeatureExtractor()

        let analysis: PhotoAnalysisResult = await service.analyze(image: cgImage)
        mainObjectImage = analysis.mainObjectImage.map {
            NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
        }

        let allMainTags = analysis.main.allTags
            .map { "\($0.label) (\($0.confidence))" }
            .joined(separator: "\n")

        let filteredVision = analysis.main.allTags
            .filter { $0.confidence > 0.5 }
            .map { "\($0.label) (\($0.confidence))" }
            .joined(separator: "\n")
        
        resultBlocks = [
            DebugResultBlock(title: "Main tags", text: allMainTags),
            DebugResultBlock(title: "Filtered features", text: filteredVision),
        ]
    }
}

private struct DebugResultBlock: Identifiable {
    let id = UUID()
    let title: String
    let text: String
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
