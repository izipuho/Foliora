import Foundation
import Observation
import UIKit

/// Represents visual keyword data and behavior.
struct VisualKeyword: Hashable, Sendable {
    let value: String
    let confidence: Double
}

/// Represents bell photo suggestions data and behavior.
struct BellPhotoSuggestions: Sendable {
    let tags: [String]
    let recognizedText: [RecognizedTextFeature]
    let visualKeywords: [VisualKeyword]
    let isBellDetected: Bool
    let title: SuggestedFieldValue<String>?
    let notes: SuggestedFieldValue<String>?
    let material: SuggestedFieldValue<BellMaterial>?
    let condition: SuggestedFieldValue<ItemCondition>?
    let customMaterialName: SuggestedFieldValue<String>?
    let suggestedYear: SuggestedFieldValue<Int>?
    let suggestedGeo: SuggestedFieldValue<GeoPoint>?
    let suggestedTags: [SuggestedFieldValue<String>]
    let debugInfo: BellPhotoAnalysisDebugInfo?

    static let empty = BellPhotoSuggestions(
        tags: [],
        recognizedText: [],
        visualKeywords: [],
        isBellDetected: false,
        title: nil,
        notes: nil,
        material: nil,
        condition: nil,
        customMaterialName: nil,
        suggestedYear: nil,
        suggestedGeo: nil,
        suggestedTags: [],
        debugInfo: nil
    )

    var hasSuggestions: Bool {
        !recognizedText.isEmpty
            || !visualKeywords.isEmpty
            || title != nil
            || notes != nil
            || material != nil
            || condition != nil
            || customMaterialName != nil
            || suggestedYear != nil
            || suggestedGeo != nil
            || !suggestedTags.isEmpty
    }
}

/// Represents bell photo analysis debug info data and behavior.
struct BellPhotoAnalysisDebugInfo: Sendable {
    let prompt: String
    let input: String
    let output: String
    let visionTags: String
    let ocrText: String

    init(prompt: String, input: String, output: String, visionTags: String = "", ocrText: String = "") {
        self.prompt = prompt
        self.input = input
        self.output = output
        self.visionTags = visionTags
        self.ocrText = ocrText
    }
}

/// Defines the interface for bell photo suggestion mapping implementations.
protocol BellPhotoSuggestionMapping: Sendable {
    func map(
        analysis: MultiPhotoAnalysisResult,
        semanticFeatures: SemanticPhotoFeatures
    ) async -> BellPhotoSuggestions
}

/// Provides default bell photo suggestion mapper operations.
struct DefaultBellPhotoSuggestionMapper: BellPhotoSuggestionMapping {
    func map(
        analysis: MultiPhotoAnalysisResult,
        semanticFeatures: SemanticPhotoFeatures
    ) async -> BellPhotoSuggestions {
        let recognizedText = analysis.photos.flatMap { $0.main.recognizedText }
        let visualFeatures = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.visualKeyword]
        )
        let visualKeywords = makeVisualKeywords(from: visualFeatures)
        let isBellDetected = isBellDetected(in: semanticFeatures.rawVisualKeywords)
        let title = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.subject]
        ).first.map {
            SuggestedFieldValue(value: $0.value, confidence: $0.confidence)
        }
        let suggestedTags = makeSuggestedTags(from: semanticFeatures)
        let tags = suggestedTags.map(\.value)
        let materialFeature = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.material]
        ).first
        let material = materialFeature.map {
            SuggestedFieldValue(value: mapMaterial($0.value), confidence: $0.confidence)
        }
        let customMaterialName = materialFeature.flatMap { feature -> SuggestedFieldValue<String>? in
            mapMaterial(feature.value) == .other
                ? SuggestedFieldValue(value: feature.value, confidence: feature.confidence)
                : nil
        }
        let condition = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.condition]
        ).first.flatMap { feature in
            mapCondition(feature.value).map { condition in
                SuggestedFieldValue(value: condition, confidence: feature.confidence)
            }
        }
        let notesFeatures = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.style, .text]
        )
        let notes = makeNotes(from: notesFeatures)
        let suggestedYear = semanticFeatures.suggestedYear.flatMap { estimate in
            estimate.year.map {
                SuggestedFieldValue(value: $0, confidence: estimate.confidence)
            }
        }
        let suggestedGeo = semanticFeatures.suggestedGeo.map {
            SuggestedFieldValue(
                value: GeoPoint(label: $0.value, name: $0.value, coordinate: nil),
                confidence: $0.confidence
            )
        }

        return BellPhotoSuggestions(
            tags: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords,
            isBellDetected: isBellDetected,
            title: title,
            notes: notes,
            material: material,
            condition: condition,
            customMaterialName: customMaterialName,
            suggestedYear: suggestedYear,
            suggestedGeo: suggestedGeo,
            suggestedTags: suggestedTags,
            debugInfo: nil
        )
    }

    private func makeVisualKeywords(from visualFeatures: [SemanticPhotoFeature]) -> [VisualKeyword] {
        visualFeatures
            .filter { $0.confidence >= 0.28 }
            .map {
                VisualKeyword(value: $0.value, confidence: $0.confidence)
            }
    }

    private func isBellDetected(in rawVisualKeywords: [String]) -> Bool {
        rawVisualKeywords.contains { keyword in
            keyword
                .lowercased()
                .split { !$0.isLetter }
                .contains("bell")
        }
    }

    private func makeSuggestedTags(from semanticFeatures: SemanticPhotoFeatures) -> [SuggestedFieldValue<String>] {
        sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.subject, .style, .place, .text, .visualKeyword]
        ).map {
            SuggestedFieldValue(value: $0.value, confidence: $0.confidence)
        }
    }

    private func makeNotes(from features: [SemanticPhotoFeature]) -> SuggestedFieldValue<String>? {
        let values = features.map(\.value)
        guard !values.isEmpty else {
            return nil
        }

        return SuggestedFieldValue(
            value: values.joined(separator: ", "),
            confidence: features.map(\.confidence).max() ?? 0
        )
    }

    private func sortedNonEmptyFeatures(
        from semanticFeatures: SemanticPhotoFeatures,
        ofKinds kinds: Set<SemanticPhotoFeatureKind>
    ) -> [SemanticPhotoFeature] {
        semanticFeatures.features
            .compactMap { feature -> SemanticPhotoFeature? in
                let value = feature.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard kinds.contains(feature.kind), !value.isEmpty else {
                    return nil
                }

                return SemanticPhotoFeature(
                    kind: feature.kind,
                    value: value,
                    confidence: feature.confidence,
                    source: feature.source
                )
            }
            .sorted { $0.confidence > $1.confidence }
    }

    private func mapMaterial(_ value: String) -> BellMaterial {
        switch normalizedEnumValue(value) {
        case BellMaterial.metall.rawValue, "metal":
            return .metall
        case BellMaterial.brass.rawValue:
            return .brass
        case BellMaterial.bronze.rawValue:
            return .bronze
        case BellMaterial.silver.rawValue:
            return .silver
        case BellMaterial.gold.rawValue:
            return .gold
        case BellMaterial.ceramic.rawValue:
            return .ceramic
        case BellMaterial.porcelain.rawValue:
            return .porcelain
        case BellMaterial.glass.rawValue:
            return .glass
        case BellMaterial.wood.rawValue:
            return .wood
        default:
            return .other
        }
    }

    private func mapCondition(_ value: String) -> ItemCondition? {
        let normalizedValue = normalizedEnumValue(value)

        return ItemCondition.allCases.first {
            normalizedEnumValue($0.rawValue) == normalizedValue
                || normalizedEnumValue(String(describing: $0)) == normalizedValue
            }
    }

    private func normalizedEnumValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

private extension SemanticPhotoFeatures {
    var rawVisualKeywords: [String] {
        features(ofKind: .visualKeyword).map(\.value)
    }
}

/// Provides bell photo analysis controller operations.
@MainActor
@Observable
final class BellPhotoAnalysisController {
    enum Field {
        case title
        case notes
        case material
        case condition
        case customMaterialName
        case suggestedYear
        case suggestedGeo
        case suggestedTags
    }

    private struct PendingPhoto {
        let assetID: UUID
        let image: CGImage
    }

    private(set) var isAnalyzing = false
    private(set) var suggestions: BellPhotoSuggestions = .empty
    private(set) var mediaSnapshot: ItemRecognitionMediaSnapshot = .empty

    private let service: any PhotoAnalysisService
    private let semanticExtractor: any SemanticPhotoFeatureExtracting
    private let mapper: any BellPhotoSuggestionMapping

    private var analysisByAssetID: [UUID: PhotoAnalysisResult] = [:]
    private var analysisOrder: [UUID] = []
    private var pendingBatches: [[PendingPhoto]] = []
    private var isProcessingBatch = false
    private var evidenceRevision = 0

    init() {
        self.service = DefaultPhotoAnalysisService()
        self.semanticExtractor = SemanticPhotoFeatureExtractor()
        self.mapper = DefaultBellPhotoSuggestionMapper()
    }

    init(
        service: any PhotoAnalysisService,
        semanticExtractor: any SemanticPhotoFeatureExtracting,
        mapper: any BellPhotoSuggestionMapping
    ) {
        self.service = service
        self.semanticExtractor = semanticExtractor
        self.mapper = mapper
    }

    var hasSuggestions: Bool {
        isAnalyzing || suggestions.hasSuggestions
    }

    func analyze(image: UIImage) {
        analyze(images: [image])
    }

    func analyze(images: [UIImage]) {
        analyze(
            photos: images.map {
                (assetID: UUID(), image: $0)
            }
        )
    }

    func analyze(photos: [(assetID: UUID, image: UIImage)]) {
        analysisByAssetID.removeAll()
        analysisOrder.removeAll()
        pendingBatches.removeAll()
        evidenceRevision += 1
        suggestions = .empty
        mediaSnapshot = ItemRecognitionMediaSnapshot(
            photoAssetIDs: Set(photos.map(\.assetID))
        )

        let pending = pendingPhotos(from: photos)
        guard !pending.isEmpty else {
            if !isProcessingBatch {
                isAnalyzing = false
            }
            return
        }

        analysisOrder = pending.map(\.assetID)
        enqueue(pending)
    }

    func analyzeAddedPhoto(assetID: UUID, image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        mediaSnapshot = ItemRecognitionMediaSnapshot(
            photoAssetIDs: mediaSnapshot.photoAssetIDs.union([assetID])
        )
        if !analysisOrder.contains(assetID) {
            analysisOrder.append(assetID)
        }
        enqueue([PendingPhoto(assetID: assetID, image: cgImage)])
    }

    func reconcileMediaSnapshot(_ snapshot: ItemRecognitionMediaSnapshot) {
        guard snapshot != mediaSnapshot else { return }

        let validAssetIDs = snapshot.photoAssetIDs
        let removedEvidence = analysisByAssetID.keys.contains { !validAssetIDs.contains($0) }
        let removedQueuedPhotos = pendingBatches.contains { batch in
            batch.contains { !validAssetIDs.contains($0.assetID) }
        }

        mediaSnapshot = snapshot
        analysisByAssetID = analysisByAssetID.filter { validAssetIDs.contains($0.key) }
        analysisOrder.removeAll { !validAssetIDs.contains($0) }
        pendingBatches = pendingBatches.compactMap { batch in
            let filtered = batch.filter { validAssetIDs.contains($0.assetID) }
            return filtered.isEmpty ? nil : filtered
        }

        guard removedEvidence || removedQueuedPhotos else { return }

        evidenceRevision += 1
        let revision = evidenceRevision

        guard !isProcessingBatch else { return }

        isAnalyzing = true
        Task {
            await refreshSuggestions(for: revision)
            guard revision == evidenceRevision else { return }
            isAnalyzing = false
        }
    }

    func dismiss(_ field: Field) {
        suggestions = BellPhotoSuggestions(
            tags: suggestions.tags,
            recognizedText: suggestions.recognizedText,
            visualKeywords: suggestions.visualKeywords,
            isBellDetected: suggestions.isBellDetected,
            title: field == .title ? nil : suggestions.title,
            notes: field == .notes ? nil : suggestions.notes,
            material: field == .material ? nil : suggestions.material,
            condition: field == .condition ? nil : suggestions.condition,
            customMaterialName: field == .customMaterialName ? nil : suggestions.customMaterialName,
            suggestedYear: field == .suggestedYear ? nil : suggestions.suggestedYear,
            suggestedGeo: field == .suggestedGeo ? nil : suggestions.suggestedGeo,
            suggestedTags: field == .suggestedTags ? [] : suggestions.suggestedTags,
            debugInfo: suggestions.debugInfo
        )
    }

    func clear() {
        analysisByAssetID.removeAll()
        analysisOrder.removeAll()
        pendingBatches.removeAll()
        evidenceRevision += 1
        suggestions = .empty
        mediaSnapshot = .empty
        if !isProcessingBatch {
            isAnalyzing = false
        }
    }

    private func pendingPhotos(
        from photos: [(assetID: UUID, image: UIImage)]
    ) -> [PendingPhoto] {
        photos.compactMap { photo in
            guard let cgImage = photo.image.cgImage else { return nil }
            return PendingPhoto(assetID: photo.assetID, image: cgImage)
        }
    }

    private func enqueue(_ photos: [PendingPhoto]) {
        guard !photos.isEmpty else { return }
        pendingBatches.append(photos)
        processNextBatchIfNeeded()
    }

    private func processNextBatchIfNeeded() {
        guard !isProcessingBatch else { return }
        guard !pendingBatches.isEmpty else {
            isAnalyzing = false
            return
        }

        let batch = pendingBatches.removeFirst()
        isProcessingBatch = true
        isAnalyzing = true

        Task {
            let analysis = await service.analyze(images: batch.map(\.image))

            for (photo, result) in zip(batch, analysis.photos) where analysisOrder.contains(photo.assetID) {
                analysisByAssetID[photo.assetID] = result
            }

            evidenceRevision += 1
            await refreshSuggestions(for: evidenceRevision)

            isProcessingBatch = false
            processNextBatchIfNeeded()
        }
    }

    private func refreshSuggestions(for revision: Int) async {
        let analysis = currentAnalysis
        guard !analysis.photos.isEmpty else {
            guard revision == evidenceRevision else { return }
            suggestions = .empty
            return
        }

        let semanticFeatures = await semanticExtractor.extractFeatures(from: analysis)
        let mapped = await mapper.map(
            analysis: analysis,
            semanticFeatures: semanticFeatures
        )

        guard revision == evidenceRevision else { return }
        suggestions = mapped
    }

    private var currentAnalysis: MultiPhotoAnalysisResult {
        MultiPhotoAnalysisResult(
            photos: analysisOrder.compactMap { analysisByAssetID[$0] }
        )
    }
}
