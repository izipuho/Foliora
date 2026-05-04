import SwiftUI
import PhotosUI

struct VisionDebugView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var resultText: String = ""

    var body: some View {
        VStack(spacing: 20) {
            PhotosPicker("Pick Photo", selection: $selectedItem, matching: .images)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
            }

            Button("Analyze") {
                Task {
                    await analyze()
                }
            }

            ScrollView {
                Text(resultText)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .padding()
        .onChange(of: selectedItem) {
            Task {
                if let data = try? await selectedItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    image = uiImage
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

        //let rawTags = analysis.tags.joined(separator: ", ")
        let vision = analysis.visionFeatures
            .map { "\($0.label) (\($0.confidence))" }
            .joined(separator: "\n")

        let ocrText = analysis.recognizedText
            .map { $0.text }
            .joined(separator: "\n")

        //let year = analysis.year.map { String($0) } ?? "-"
        //let geo = analysis.geo?.name ?? "-"

        let suggestedTags = suggestions.suggestedTags
            .map { $0.value }
            .joined(separator: ", ")

        let suggestedYear = suggestions.suggestedYear.map { String($0.value) } ?? "-"
        let suggestedGeo = suggestions.suggestedGeo?.value.name ?? "-"

        resultText = """
        VISION FEATURES:
        \(vision)

        OCR:
        \(ocrText)

        -----

        SUGGESTED TAGS:
        \(suggestedTags)

        SUGGESTED YEAR:
        \(suggestedYear)

        SUGGESTED GEO:
        \(suggestedGeo)
        """
    }
}