import SwiftUI
import PhotosUI
import UIKit

struct VisionDebugView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var mainObjectImage: UIImage?
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
                   let uiImage = UIImage(data: data) {
                    image = uiImage
                    mainObjectImage = nil
                    await analyze()
                }
            }
        }
    }

    private func analyze() async {
        guard let image else { return }

        let service = DefaultPhotoAnalysisService()
        let mapper = DefaultBellPhotoSuggestionMapper()

        let analysis: PhotoAnalysisResult = await service.analyze(image: image)
        let suggestions: BellPhotoSuggestions = await mapper.map(analysis: analysis)
        mainObjectImage = analysis.mainObjectImage

        let mainVision = analysis.main.visionFeatures
            .map { "\($0.label) (\($0.confidence))" }
            .joined(separator: "\n")

        let mainAnimals = analysis.main.animalHints
            .map { "\($0.label) (\($0.confidence))" }
            .joined(separator: "\n")

        let allMainTags = analysis.main.allTags
            .map { "\($0.label) (\($0.confidence))" }
            .joined(separator: "\n")

        let backgroundVision = analysis.background.visionFeatures
            .map { "\($0.label) (\($0.confidence))" }
            .joined(separator: "\n")

        let filteredVision = analysis.main.allTags
            .filter { $0.confidence > 0.5 }
            .map { "\($0.label) (\($0.confidence))" }
            .joined(separator: "\n")
        
        let ocrText = analysis.main.recognizedText
            .map { $0.text }
            .joined(separator: "\n")

        let suggestedTags = suggestions.suggestedTags
            .map { $0.value }
            .joined(separator: ", ")

        let suggestedYear = suggestions.suggestedYear.map { String($0.value) } ?? "-"
        let suggestedGeo = suggestions.suggestedGeo?.value.name ?? "-"

        resultBlocks = [
            DebugResultBlock(title: "Main tags", text: allMainTags),
            DebugResultBlock(title: "Main visionFeatures", text: mainVision),
            DebugResultBlock(title: "Animals", text: mainAnimals),
            DebugResultBlock(title: "Filtered features", text: filteredVision),
            DebugResultBlock(title: "OCR", text: ocrText),
            DebugResultBlock(title: "SUGGESTED TAGS", text: suggestedTags),
            DebugResultBlock(title: "SUGGESTED YEAR", text: suggestedYear),
            DebugResultBlock(title: "SUGGESTED GEO", text: suggestedGeo)
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
    let image: UIImage

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(uiImage: image)
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
                    UIPasteboard.general.string = block.text
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .padding(8)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
