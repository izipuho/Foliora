import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Immutable recognition output converted into an editor-owned text fragment.
struct TextFragmentSource {
    let text: String
    let confidence: Double
    let boundingBox: CGRect
    let sourceIndex: Int
}

/// Mutable text fragment that can be assigned, split, removed, and dragged between editor targets.
struct TextFragment: Identifiable, Hashable {
    let id: UUID
    var text: String
    let confidence: Double
    let boundingBox: CGRect
    let sourceIndex: Int?

    static func == (lhs: TextFragment, rhs: TextFragment) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func readingOrder(_ lhs: TextFragment, _ rhs: TextFragment) -> Bool {
        let lhsRow = Int((lhs.boundingBox.midY * 50).rounded())
        let rhsRow = Int((rhs.boundingBox.midY * 50).rounded())
        if lhsRow != rhsRow {
            return lhsRow > rhsRow
        }
        if lhs.boundingBox.minX != rhs.boundingBox.minX {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Carries only one editor fragment identity during an in-process drag.
struct TextFragmentTransfer: Codable, Sendable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
            .visibility(.ownProcess)
    }
}

/// Owns mutable text fragments and their assignments independently of any concrete editor fields.
struct TextFragmentState<Target: Hashable> {
    var fragments: [TextFragment] = []
    var assignments: [Target: [TextFragment]] = [:]
    var consumedFragmentIDs: Set<UUID> = []

    var usedFragmentIDs: Set<UUID> {
        var usedIDs = Set(assignments.values.flatMap { $0 }.map(\.id))
        usedIDs.formUnion(consumedFragmentIDs)
        return usedIDs
    }

    var hasUnusedFragments: Bool {
        fragments.contains { !usedFragmentIDs.contains($0.id) }
    }

    mutating func sync(from sources: [TextFragmentSource]) {
        for source in sources
        where !fragments.contains(where: { $0.sourceIndex == source.sourceIndex }) {
            fragments.append(
                TextFragment(
                    id: UUID(),
                    text: source.text,
                    confidence: source.confidence,
                    boundingBox: source.boundingBox,
                    sourceIndex: source.sourceIndex
                )
            )
        }
        fragments.sort(by: TextFragment.readingOrder)
    }

    func matching(_ transfers: [TextFragmentTransfer]) -> [TextFragment] {
        transfers.compactMap { transfer in
            fragments.first { $0.id == transfer.id }
        }
    }

    func mergedAssignment(
        adding newFragments: [TextFragment],
        to target: Target
    ) -> [TextFragment] {
        var assigned = assignments[target, default: []]
        for fragment in newFragments where !assigned.contains(fragment) {
            assigned.append(fragment)
        }
        assigned.sort(by: TextFragment.readingOrder)
        return assigned
    }

    mutating func setAssignment(_ fragments: [TextFragment], for target: Target) {
        if fragments.isEmpty {
            assignments.removeValue(forKey: target)
        } else {
            assignments[target] = fragments
        }
    }

    @discardableResult
    mutating func remove(_ fragment: TextFragment, from target: Target) -> [TextFragment] {
        var assigned = assignments[target, default: []]
        assigned.removeAll { $0.id == fragment.id }
        assigned.sort(by: TextFragment.readingOrder)
        setAssignment(assigned, for: target)
        return assigned
    }

    @discardableResult
    mutating func consumeAssignment(for target: Target) -> [TextFragment] {
        let assigned = assignments.removeValue(forKey: target) ?? []
        consumedFragmentIDs.formUnion(assigned.map(\.id))
        return assigned
    }

    mutating func split(
        _ fragment: TextFragment,
        extracting range: Range<String.Index>,
        replacementText: String
    ) -> TextFragment {
        let remainder = String(fragment.text[..<range.lowerBound] + fragment.text[range.upperBound...])
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        guard !remainder.isEmpty else { return fragment }

        if let index = fragments.firstIndex(where: { $0.id == fragment.id }) {
            fragments[index].text = remainder
        }

        let extractedFragment = TextFragment(
            id: UUID(),
            text: replacementText,
            confidence: fragment.confidence,
            boundingBox: fragment.boundingBox,
            sourceIndex: nil
        )
        fragments.append(extractedFragment)
        fragments.sort(by: TextFragment.readingOrder)
        return extractedFragment
    }
}
