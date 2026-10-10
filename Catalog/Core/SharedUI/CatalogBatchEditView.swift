import SwiftUI

/// Hosts fields shared by all catalog batch editors and optional domain-specific sections.
struct CatalogBatchEditView<DomainContent: View>: View {
    let isDomainEditEmpty: Bool
    let isDomainEditValid: Bool
    let onSave: (ItemBatchEdit) -> Void
    private let domainContent: () -> DomainContent

    @Environment(\.dismiss) private var dismiss
    @State private var condition: ItemCondition?
    @State private var acquisitionMethod: AcquisitionMethod?
    @State private var acquiredYearText = ""
    @State private var acquiredYearShouldClear = false

    init(
        isDomainEditEmpty: Bool,
        isDomainEditValid: Bool = true,
        onSave: @escaping (ItemBatchEdit) -> Void,
        @ViewBuilder domainContent: @escaping () -> DomainContent
    ) {
        self.isDomainEditEmpty = isDomainEditEmpty
        self.isDomainEditValid = isDomainEditValid
        self.onSave = onSave
        self.domainContent = domainContent
    }

    var body: some View {
        NavigationStack {
            Form {
                domainContent()

                Section(String(localized: "catalog.batch_edit.fields")) {
                    Picker(String(localized: "common.field.condition"), selection: $condition) {
                        Text(String(localized: "catalog.batch_edit.keep_unchanged"))
                            .tag(nil as ItemCondition?)
                        ForEach(ItemCondition.allCases) { value in
                            Text(value.displayName)
                                .tag(Optional(value))
                        }
                    }

                    Picker(String(localized: "item.detail.acquisition"), selection: $acquisitionMethod) {
                        Text(String(localized: "catalog.batch_edit.keep_unchanged"))
                            .tag(nil as AcquisitionMethod?)
                        ForEach(AcquisitionMethod.allCases) { value in
                            Text(value.displayName)
                                .tag(Optional(value))
                        }
                    }

                    LabeledContent(String(localized: "item.detail.acquisition_year")) {
                        HStack(spacing: 8) {
                            TextField("", text: acquiredYearBinding)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)

                            Button {
                                acquiredYearText = ""
                                acquiredYearShouldClear = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .opacity(acquiredYearShouldClear ? 1 : 0.35)
                            .accessibilityLabel(String(localized: "common.clear"))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "catalog.batch_edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(batchEdit)
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

    private var canSave: Bool {
        (isDomainEditEmpty == false || batchEdit.isEmpty == false)
            && isDomainEditValid
            && isAcquiredYearValid
    }

    private var batchEdit: ItemBatchEdit {
        ItemBatchEdit(
            acquiredYear: acquiredYearChange,
            condition: condition,
            acquisitionMethod: acquisitionMethod
        )
    }

    private var acquiredYearBinding: Binding<String> {
        Binding(
            get: { acquiredYearText },
            set: { value in
                acquiredYearText = value
                acquiredYearShouldClear = false
            }
        )
    }

    private var acquiredYearChange: BatchEditValue<Int> {
        if acquiredYearShouldClear {
            return .set(nil)
        }

        let trimmed = acquiredYearText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unchanged }
        return .set(Int(trimmed))
    }

    private var isAcquiredYearValid: Bool {
        guard !acquiredYearShouldClear else { return true }

        let trimmed = acquiredYearText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let year = Int(trimmed) else { return false }

        let maximumYear = Calendar.current.component(.year, from: Date()) + 1
        return (1...maximumYear).contains(year)
    }
}
