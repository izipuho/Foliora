import CoreGraphics
import Foundation
import Testing
@testable import Foliora_Books

struct BookTextAssignmentControllerTests {
    @Test
    func syncPreservesProvidedSourceOrderAcrossPhotoCoordinateSpaces() {
        var controller = BookTextAssignmentController()
        controller.sync(from: [
            recognizedText(
                "photo one lower text",
                boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.1)
            ),
            recognizedText(
                "photo two upper text",
                boundingBox: CGRect(x: 0.1, y: 0.85, width: 0.8, height: 0.1)
            )
        ])

        #expect(controller.fragments.map(\.text) == [
            "photo one lower text",
            "photo two upper text"
        ])
    }

    @Test
    func extractsVolumeAndKeepsRemainderAsUnusedFragment() {
        var controller = BookTextAssignmentController()
        controller.sync(from: [recognizedText("Том 12")])

        let original = controller.fragments.first
        #expect(original != nil)
        guard let original else { return }

        let prepared = controller.prepareAssignment(
            [TextFragmentTransfer(id: original.id)],
            to: .field(.volume)
        )
        #expect(prepared != nil)
        guard let prepared else { return }

        #expect(prepared.assignment.text == "12")
        controller.commit(prepared)
        #expect(controller.assignment(for: .field(.volume))?.map(\.text) == ["12"])
        #expect(controller.fragments.contains(where: { $0.text == "Том" }))
        #expect(controller.hasUnusedFragments)
    }

    @Test
    func extractsPublicationYearFromMixedText() {
        var controller = BookTextAssignmentController()
        controller.sync(from: [recognizedText("Издание 1984")])

        let original = controller.fragments.first
        #expect(original != nil)
        guard let original else { return }

        let prepared = controller.prepareAssignment(
            [TextFragmentTransfer(id: original.id)],
            to: .field(.publicationYear)
        )
        #expect(prepared?.assignment.text == "1984")
    }

    @Test
    func remapsAuthorAssignmentsAndBaseNamesAfterDeletion() {
        let first = fragment("First")
        let second = fragment("Second")
        var controller = BookTextAssignmentController()
        controller.setAssignment([first], for: .author(0))
        controller.setAssignment([second], for: .author(2))
        controller.setAuthorBaseName("Author Zero", for: 0)
        controller.setAuthorBaseName("Author Two", for: 2)

        controller.remapAuthors(survivingIndices: [2])

        #expect(controller.authorIndices == [0])
        #expect(controller.assignment(for: .author(0))?.map(\.text) == ["Second"])
        #expect(controller.assignment(for: .author(2)) == nil)
        #expect(controller.authorBaseName(for: 0) == "Author Two")
        #expect(controller.authorBaseName(for: 2) == nil)
    }

    @Test
    func removingLastFragmentDeletesOcrCreatedAuthor() {
        let assigned = fragment("Author")
        var controller = BookTextAssignmentController()
        controller.setAssignment([assigned], for: .author(1))
        controller.setAuthorBaseName("", for: 1)

        let action = controller.remove(assigned, from: .author(1))

        switch action {
        case .deleteAuthor(let index):
            #expect(index == 1)
        case .apply:
            #expect(Bool(false), "Expected OCR-created author to be deleted")
        }
    }

    private func recognizedText(
        _ text: String,
        boundingBox: CGRect = .zero
    ) -> RecognizedTextFeature {
        RecognizedTextFeature(
            text: text,
            confidence: 0.9,
            boundingBox: boundingBox
        )
    }

    private func fragment(_ text: String) -> TextFragment {
        TextFragment(
            id: UUID(),
            text: text,
            confidence: 1,
            boundingBox: .zero,
            sourceIndex: nil
        )
    }
}