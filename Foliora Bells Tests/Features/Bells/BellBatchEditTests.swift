import Foundation
import Testing
@testable import Foliora_Bells

struct BellBatchEditTests {
    private let details = BellDetails(
        itemID: UUID(),
        material: .glass,
        customMaterialName: nil,
        color: .green,
        size: .m
    )

    @Test
    func sizeOnlyEditKeepsMaterial() {
        let updated = BellBatchEdit(size: .l).applying(to: details)

        #expect(updated.size == .l)
        #expect(updated.material == .glass)
        #expect(updated.color == .green)
    }

    @Test
    func materialOnlyEditKeepsSize() {
        let updated = BellBatchEdit(material: .bronze).applying(to: details)

        #expect(updated.material == .bronze)
        #expect(updated.size == .m)
        #expect(updated.color == .green)
    }

    @Test
    func emptyEditIsEmpty() {
        #expect(BellBatchEdit().isEmpty)
        #expect(!BellBatchEdit(size: .s).isEmpty)
    }
}
