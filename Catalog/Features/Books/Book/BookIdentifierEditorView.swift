import Foundation
import SwiftUI

struct BookIdentifierEditorView: View {
    let identifier: BookIdentifier?
    let existingIdentifiers: [BookIdentifier]
    let editingIndex: Int?
    let onSave: (BookIdentifier) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type: BookIdentifierType
    @State private var value: String

    init(
        identifier: BookIdentifier?,
        existingIdentifiers: [BookIdentifier],
        editingIndex: Int?,
        onSave: @escaping (BookIdentifier) -> Void
    ) {
        self.identifier = identifier
        self.existingIdentifiers = existingIdentifiers
        self.editingIndex = editingIndex
        self.onSave = onSave
        _type = State(initialValue: identifier?.type ?? .isbn13)
        _value = State(initialValue: identifier?.value ?? "")
    }

    private var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        guard !trimmedValue.isEmpty else { return false }
        let key = bookIdentifierDuplicateKey(type: type, value: trimmedValue)

        return existingIdentifiers.enumerated().contains { index, existing in
            index != editingIndex
                && existing.type == type
                && bookIdentifierDuplicateKey(type: existing.type, value: existing.value) == key
        }
    }

    private var validationMessage: String? {
        guard !trimmedValue.isEmpty else {
            return String(localized: "book_identifier.validation.value_required")
        }

        switch type {
        case .isbn10:
            guard isValidISBN10(trimmedValue) else {
                return String(localized: "book_identifier.validation.isbn10_invalid")
            }
        case .isbn13:
            guard isValidISBN13(trimmedValue) else {
                return String(localized: "book_identifier.validation.isbn13_invalid")
            }
        case .sbn, .asin, .inventory, .other:
            break
        }

        if isDuplicate {
            return String(localized: "book_identifier.validation.duplicate")
        }

        return nil
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("book_identifier.title") {
                    Picker("common.type", selection: $type) {
                        ForEach(BookIdentifierType.allCases) { type in
                            Text(type.bookEditorDisplayName).tag(type)
                        }
                    }

                    TextField("book_identifier.field.value", text: $value)

                    if let validationMessage {
                        Label(
                            validationMessage,
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(CatalogSemanticColors.destructive)
                    }
                }
            }
            .navigationTitle(identifier == nil ? String(localized: "book_identifier.action.add") : String(localized: "book_identifier.action.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(BookIdentifier(type: type, value: trimmedValue))
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
        }
    }
}

extension BookIdentifierType {
    var bookEditorDisplayName: String {
        switch self {
        case .isbn10: "ISBN-10"
        case .isbn13: "ISBN-13"
        case .sbn: "SBN"
        case .asin: "ASIN"
        case .inventory: String(localized: "book.field.inventory")
        case .other: String(localized: "common.other")
        }
    }
}

private func compactBookIdentifier(_ value: String) -> String {
    value.filter { $0.isLetter || $0.isNumber }.uppercased()
}

func bookIdentifierDuplicateKey(type: BookIdentifierType, value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    switch type {
    case .isbn10, .isbn13, .sbn:
        return compactBookIdentifier(trimmed)
    case .asin:
        return trimmed.uppercased()
    case .inventory, .other:
        return trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}

private func isValidISBN10(_ value: String) -> Bool {
    let characters = Array(compactBookIdentifier(value))
    guard characters.count == 10 else { return false }
    guard characters.dropLast().allSatisfy(\.isNumber), let last = characters.last else { return false }
    return last.isNumber || last == "X"
}

private func isValidISBN13(_ value: String) -> Bool {
    let characters = Array(compactBookIdentifier(value))
    return characters.count == 13 && characters.allSatisfy(\.isNumber)
}
