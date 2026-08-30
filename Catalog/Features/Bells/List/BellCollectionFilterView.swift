import SwiftUI

private enum BellPresenceRequirement: String, CaseIterable, Identifiable {
    case any
    case present
    case missing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .present: return "Present"
        case .missing: return "Missing"
        }
    }
}

struct BellCollectionFilterView: View {
    let bells: [BellListItem]
    let onApply: (BellFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftFilters: BellFilters

    init(
        bells: [BellListItem],
        filters: BellFilters,
        onApply: @escaping (BellFilters) -> Void
    ) {
        self.bells = bells
        self.onApply = onApply
        _draftFilters = State(initialValue: filters)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Catalog") {
                    singleSelectionLink(
                        title: "Country",
                        systemImage: "globe.europe.africa",
                        values: countries,
                        selection: countryBinding,
                        label: { $0 }
                    )

                    singleSelectionLink(
                        title: "Material",
                        systemImage: "square.stack.3d.up",
                        values: materials,
                        selection: materialBinding,
                        label: { $0 }
                    )

                    singleSelectionLink(
                        title: "Tag",
                        systemImage: "tag",
                        values: tags,
                        selection: tagBinding,
                        label: { $0 }
                    )

                    singleSelectionLink(
                        title: "Condition",
                        systemImage: "checkmark.seal",
                        values: conditions,
                        selection: conditionBinding,
                        label: { $0.displayName }
                    )

                    singleSelectionLink(
                        title: "Acquisition",
                        systemImage: "bag",
                        values: acquisitionMethods,
                        selection: acquisitionMethodBinding,
                        label: { $0.displayName }
                    )
                }

                Section("Data") {
                    presencePicker(
                        title: "Origin",
                        systemImage: "mappin.and.ellipse",
                        selection: presenceBinding(present: .withOrigin, missing: .missingOrigin)
                    )
                    presencePicker(
                        title: "Acquired year",
                        systemImage: "calendar",
                        selection: presenceBinding(present: .withYear, missing: .missingYear)
                    )
                    presencePicker(
                        title: "Storage",
                        systemImage: "archivebox",
                        selection: presenceBinding(present: .withStorage, missing: .missingStorage)
                    )
                    presencePicker(
                        title: "Notes",
                        systemImage: "note.text",
                        selection: presenceBinding(present: .withNotes, missing: .missingNotes)
                    )
                    presencePicker(
                        title: "Tags",
                        systemImage: "tag",
                        selection: presenceBinding(present: .withTags, missing: .missingTags)
                    )
                    presencePicker(
                        title: "Material",
                        systemImage: "square.stack.3d.up",
                        selection: presenceBinding(present: .withMaterial, missing: .missingMaterial)
                    )

                    Toggle("Has city", isOn: cityBinding)
                }

                if !draftFilters.isEmpty {
                    Section {
                        Button("Clear All", role: .destructive) {
                            draftFilters = BellFilters()
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.apply")) {
                        onApply(draftFilters)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func singleSelectionLink<Value: Hashable>(
        title: String,
        systemImage: String,
        values: [Value],
        selection: Binding<Value?>,
        label: @escaping (Value) -> String
    ) -> some View {
        if !values.isEmpty {
            NavigationLink {
                BellSingleFilterSelectionView(
                    title: title,
                    values: values,
                    selection: selection,
                    label: label
                )
            } label: {
                HStack {
                    Label(title, systemImage: systemImage)
                    Spacer()
                    if let value = selection.wrappedValue {
                        Text(label(value))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func presencePicker(
        title: String,
        systemImage: String,
        selection: Binding<BellPresenceRequirement>
    ) -> some View {
        Picker(selection: selection) {
            ForEach(BellPresenceRequirement.allCases) { requirement in
                Text(requirement.title).tag(requirement)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private var countries: [String] {
        uniqueValues(bells.map(\.countryName))
    }

    private var materials: [String] {
        uniqueValues(bells.map(\.materialDisplayName))
    }

    private var tags: [String] {
        uniqueValues(bells.flatMap(\.tagValues))
    }

    private var conditions: [ItemCondition] {
        ItemCondition.allCases.filter { condition in
            bells.contains { $0.condition == condition }
        }
    }

    private var acquisitionMethods: [AcquisitionMethod] {
        AcquisitionMethod.allCases.filter { method in
            bells.contains { $0.acquisitionMethod == method }
        }
    }

    private var countryBinding: Binding<String?> {
        attributeBinding(
            value: { attribute in
                if case .country(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.country
        )
    }

    private var materialBinding: Binding<String?> {
        attributeBinding(
            value: { attribute in
                if case .material(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.material
        )
    }

    private var tagBinding: Binding<String?> {
        attributeBinding(
            value: { attribute in
                if case .tag(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.tag
        )
    }

    private var conditionBinding: Binding<ItemCondition?> {
        attributeBinding(
            value: { attribute in
                if case .condition(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.condition
        )
    }

    private var acquisitionMethodBinding: Binding<AcquisitionMethod?> {
        attributeBinding(
            value: { attribute in
                if case .acquisitionMethod(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.acquisitionMethod
        )
    }

    private func attributeBinding<Value: Hashable>(
        value: @escaping (BellAttributeFilter) -> Value?,
        make: @escaping (Value) -> BellAttributeFilter
    ) -> Binding<Value?> {
        Binding(
            get: {
                draftFilters.attributes.compactMap(value).first
            },
            set: { newValue in
                draftFilters.attributes = Set(
                    draftFilters.attributes.filter { value($0) == nil }
                )
                if let newValue {
                    draftFilters.attributes.insert(make(newValue))
                }
            }
        )
    }

    private func presenceBinding(
        present: BellPresenceFilter,
        missing: BellPresenceFilter
    ) -> Binding<BellPresenceRequirement> {
        Binding(
            get: {
                if draftFilters.presence.contains(present) { return .present }
                if draftFilters.presence.contains(missing) { return .missing }
                return .any
            },
            set: { requirement in
                draftFilters.presence.remove(present)
                draftFilters.presence.remove(missing)

                switch requirement {
                case .any:
                    break
                case .present:
                    draftFilters.presence.insert(present)
                case .missing:
                    draftFilters.presence.insert(missing)
                }
            }
        )
    }

    private var cityBinding: Binding<Bool> {
        Binding(
            get: { draftFilters.presence.contains(.withCity) },
            set: { enabled in
                if enabled {
                    draftFilters.presence.insert(.withCity)
                } else {
                    draftFilters.presence.remove(.withCity)
                }
            }
        )
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []

        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(normalized($0)).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct BellSingleFilterSelectionView<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value?
    let label: (Value) -> String

    var body: some View {
        List {
            Button {
                selection = nil
            } label: {
                selectionRow(title: "Any", isSelected: selection == nil)
            }

            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    selectionRow(title: label(value), isSelected: selection == value)
                }
            }
        }
        .buttonStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func selectionRow(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
    }
}
