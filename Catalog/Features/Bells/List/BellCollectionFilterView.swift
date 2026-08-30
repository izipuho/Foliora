import SwiftUI

private extension BellPresenceFilter {
    var title: String {
        switch self {
        case .withOrigin:
            return String(localized: "bell_catalog.summary.with_origin")
        case .missingOrigin:
            return String(localized: "bell_catalog.summary.missing_origin")
        case .withYear:
            return String(localized: "bell_catalog.summary.with_year")
        case .missingYear:
            return String(localized: "bell_catalog.summary.missing_year")
        case .withCity:
            return String(localized: "bell_catalog.summary.with_city")
        case .withStorage:
            return String(localized: "bell_catalog.summary.with_storage")
        case .missingStorage:
            return String(localized: "bell_catalog.summary.missing_storage")
        case .withNotes:
            return String(localized: "bell_catalog.summary.with_notes")
        case .missingNotes:
            return String(localized: "bell_catalog.summary.missing_notes")
        case .withTags:
            return String(localized: "bell_catalog.summary.with_tags")
        case .missingTags:
            return String(localized: "bell_catalog.summary.missing_tags")
        case .withMaterial:
            return String(localized: "bell_catalog.summary.with_material")
        case .missingMaterial:
            return String(localized: "bell_catalog.summary.missing_material")
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
                Section {
                    filterLink(
                        title: String(localized: "bell_catalog.summary.countries"),
                        systemImage: "globe.europe.africa",
                        values: countries,
                        selection: countrySelection,
                        label: { $0 }
                    )

                    filterLink(
                        title: String(localized: "common.field.material"),
                        systemImage: "square.stack.3d.up",
                        values: materials,
                        selection: materialSelection,
                        label: { $0 }
                    )

                    filterLink(
                        title: String(localized: "common.field.tags"),
                        systemImage: "tag",
                        values: tags,
                        selection: tagSelection,
                        label: { $0 }
                    )

                    filterLink(
                        title: String(localized: "common.field.condition"),
                        systemImage: "checkmark.seal",
                        values: conditions,
                        selection: conditionSelection,
                        label: { $0.displayName }
                    )

                    filterLink(
                        title: String(localized: "item.detail.acquisition"),
                        systemImage: "bag",
                        values: acquisitionMethods,
                        selection: acquisitionMethodSelection,
                        label: { $0.displayName }
                    )
                }

                Section(String(localized: "catalog.dashboard.health")) {
                    NavigationLink {
                        CatalogFilterSelectionView(
                            title: String(localized: "catalog.dashboard.health"),
                            values: presenceFilters,
                            selection: presenceSelection,
                            label: { $0.title }
                        )
                    } label: {
                        filterLabel(
                            title: String(localized: "catalog.dashboard.health"),
                            systemImage: "checklist",
                            count: draftFilters.presence.count
                        )
                    }
                }

                if !draftFilters.isEmpty {
                    Section {
                        Button(String(localized: "common.clear"), role: .destructive) {
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
    private func filterLink<Value: Hashable>(
        title: String,
        systemImage: String,
        values: [Value],
        selection: Binding<Set<Value>>,
        label: @escaping (Value) -> String
    ) -> some View {
        if !values.isEmpty {
            NavigationLink {
                CatalogFilterSelectionView(
                    title: title,
                    values: values,
                    selection: selection,
                    label: label
                )
            } label: {
                filterLabel(
                    title: title,
                    systemImage: systemImage,
                    count: selection.wrappedValue.count
                )
            }
        }
    }

    private func filterLabel(
        title: String,
        systemImage: String,
        count: Int
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if count > 0 {
                Text(String(count))
                    .foregroundStyle(.secondary)
            }
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

    private var presenceFilters: [BellPresenceFilter] {
        [
            .withOrigin,
            .missingOrigin,
            .withYear,
            .missingYear,
            .withCity,
            .withStorage,
            .missingStorage,
            .withNotes,
            .missingNotes,
            .withTags,
            .missingTags,
            .withMaterial,
            .missingMaterial
        ]
    }

    private var countrySelection: Binding<Set<String>> {
        attributeSelection(
            value: { attribute in
                if case .country(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.country
        )
    }

    private var materialSelection: Binding<Set<String>> {
        attributeSelection(
            value: { attribute in
                if case .material(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.material
        )
    }

    private var tagSelection: Binding<Set<String>> {
        attributeSelection(
            value: { attribute in
                if case .tag(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.tag
        )
    }

    private var conditionSelection: Binding<Set<ItemCondition>> {
        attributeSelection(
            value: { attribute in
                if case .condition(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.condition
        )
    }

    private var acquisitionMethodSelection: Binding<Set<AcquisitionMethod>> {
        attributeSelection(
            value: { attribute in
                if case .acquisitionMethod(let value) = attribute { return value }
                return nil
            },
            make: BellAttributeFilter.acquisitionMethod
        )
    }

    private var presenceSelection: Binding<Set<BellPresenceFilter>> {
        Binding(
            get: { draftFilters.presence },
            set: { newSelection in
                draftFilters.presence = normalizedPresenceSelection(newSelection)
            }
        )
    }

    private func attributeSelection<Value: Hashable>(
        value: @escaping (BellAttributeFilter) -> Value?,
        make: @escaping (Value) -> BellAttributeFilter
    ) -> Binding<Set<Value>> {
        Binding(
            get: {
                Set(draftFilters.attributes.compactMap(value))
            },
            set: { selection in
                let previous = Set(draftFilters.attributes.compactMap(value))
                let selectedValue = selection.subtracting(previous).first ?? selection.first
                let retained = draftFilters.attributes.filter { value($0) == nil }
                draftFilters.attributes = Set(retained)
                if let selectedValue {
                    draftFilters.attributes.insert(make(selectedValue))
                }
            }
        )
    }

    private func normalizedPresenceSelection(
        _ selection: Set<BellPresenceFilter>
    ) -> Set<BellPresenceFilter> {
        var normalized = selection

        for pair in presencePairs {
            guard normalized.contains(pair.present), normalized.contains(pair.missing) else {
                continue
            }

            let presentWasSelected = !draftFilters.presence.contains(pair.present)
            if presentWasSelected {
                normalized.remove(pair.missing)
            } else {
                normalized.remove(pair.present)
            }
        }

        return normalized
    }

    private var presencePairs: [(present: BellPresenceFilter, missing: BellPresenceFilter)] {
        [
            (.withOrigin, .missingOrigin),
            (.withYear, .missingYear),
            (.withStorage, .missingStorage),
            (.withNotes, .missingNotes),
            (.withTags, .missingTags),
            (.withMaterial, .missingMaterial)
        ]
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
