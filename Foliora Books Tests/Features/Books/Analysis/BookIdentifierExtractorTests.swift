import CoreGraphics
import Testing
@testable import Foliora_Books

struct BookIdentifierExtractorTests {
    @Test
    func recognizesValidISBN13FromBarcode() {
        let result = extract(
            mainBarcodes: [barcode("9780804178747", confidence: 0.99)]
        )

        #expect(result.map(\.value) == [
            BookIdentifier(type: .isbn13, value: "9780804178747")
        ])
    }

    @Test
    func recognizesValid979ISBN13FromBarcode() {
        let result = extract(
            mainBarcodes: [barcode("9791090636071")]
        )

        #expect(result.map(\.value) == [
            BookIdentifier(type: .isbn13, value: "9791090636071")
        ])
    }

    @Test
    func rejectsISBN13WithInvalidCheckDigit() {
        let result = extract(
            mainBarcodes: [barcode("9789012345678")]
        )

        #expect(result.isEmpty)
    }

    @Test
    func rejectsValidEAN13ThatIsNotABookIdentifier() {
        let result = extract(
            mainBarcodes: [barcode("4006381333931")]
        )

        #expect(result.isEmpty)
    }

    @Test
    func rejects9790ISMNRange() {
        let result = extract(
            mainBarcodes: [barcode("9790123456785")]
        )

        #expect(result.isEmpty)
    }

    @Test
    func recognizesNumericISBN10FromOCR() {
        let result = extract(
            mainText: [text("ISBN 0-306-40615-2")]
        )

        #expect(result.map(\.value) == [
            BookIdentifier(type: .isbn10, value: "0306406152")
        ])
    }

    @Test
    func recognizesISBN10EndingInXAndNormalizesCase() {
        let result = extract(
            mainText: [text("ISBN: 0-804-42957-x")]
        )

        #expect(result.map(\.value) == [
            BookIdentifier(type: .isbn10, value: "080442957X")
        ])
    }

    @Test
    func rejectsISBN10WithInvalidCheckDigit() {
        let result = extract(
            mainText: [text("ISBN 1234567890")]
        )

        #expect(result.isEmpty)
    }

    @Test
    func normalizesSpacesAndHyphensInOCRISBN13() {
        let result = extract(
            mainText: [text("ISBN: 978 0-8041 7874-7.")]
        )

        #expect(result.map(\.value) == [
            BookIdentifier(type: .isbn13, value: "9780804178747")
        ])
    }

    @Test
    func prefersBarcodeEvidenceOverDuplicateOCRValue() {
        let result = extract(
            mainBarcodes: [barcode("9780804178747", confidence: 0.42)],
            mainText: [text("ISBN 978-0-8041-7874-7", confidence: 0.98)]
        )

        #expect(result.count == 1)
        #expect(result.first?.value == BookIdentifier(type: .isbn13, value: "9780804178747"))
        #expect(result.first?.confidence == 0.42)
    }

    @Test
    func extractsEvidenceFromMainAndBackgroundScopes() {
        let result = extract(
            mainBarcodes: [barcode("9780804178747", confidence: 0.9)],
            backgroundText: [text("ISBN 0-306-40615-2", confidence: 0.8)]
        )

        #expect(result.map(\.value) == [
            BookIdentifier(type: .isbn13, value: "9780804178747"),
            BookIdentifier(type: .isbn10, value: "0306406152")
        ])
    }

    private func extract(
        mainBarcodes: [RecognizedBarcodeFeature] = [],
        backgroundBarcodes: [RecognizedBarcodeFeature] = [],
        mainText: [RecognizedTextFeature] = [],
        backgroundText: [RecognizedTextFeature] = []
    ) -> [SuggestedFieldValue<BookIdentifier>] {
        let analysis = PhotoAnalysisResult(
            mainObjectImage: nil,
            mainObjectRegion: nil,
            main: scope(barcodes: mainBarcodes, text: mainText),
            background: scope(barcodes: backgroundBarcodes, text: backgroundText)
        )

        return BookIdentifierExtractor().extract(from: analysis)
    }

    private func scope(
        barcodes: [RecognizedBarcodeFeature],
        text: [RecognizedTextFeature]
    ) -> PhotoAnalysisFeatureScope {
        PhotoAnalysisFeatureScope(
            classifications: [],
            recognizedText: text,
            recognizedObjects: [],
            recognizedBarcodes: barcodes
        )
    }

    private func barcode(
        _ payload: String,
        confidence: Double = 1
    ) -> RecognizedBarcodeFeature {
        RecognizedBarcodeFeature(
            payload: payload,
            symbology: "VNBarcodeSymbologyEAN13",
            confidence: confidence,
            boundingBox: .zero
        )
    }

    private func text(
        _ value: String,
        confidence: Double = 1
    ) -> RecognizedTextFeature {
        RecognizedTextFeature(
            text: value,
            confidence: confidence,
            boundingBox: .zero
        )
    }
}
