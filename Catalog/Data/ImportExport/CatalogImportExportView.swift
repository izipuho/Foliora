import CoreData
import SwiftUI
import UniformTypeIdentifiers

typealias CollectionID = UUID

struct CatalogExportView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var homeEntities: FetchedResults<NSManagedObject>
    @FetchRequest private var collectionEntities: FetchedResults<NSManagedObject>

    @State private var selectedCollectionIDs: Set<CollectionID> = []
    @State private var didPrepareInitialSelection = false
    @State private var exportDocument: CatalogTransferDocument?
    @State private var isExportingDocument = false
    @State private var isPreparingExport = false
    @State private var exportErrorMessage: String?

    init() {
        _homeEntities = FetchRequest(fetchRequest: Self.homeFetchRequest)
        _collectionEntities = FetchRequest(fetchRequest: Self.collectionFetchRequest)
    }

    var body: some View {
        content
            .navigationTitle("catalog.export.title")
            .toolbar {
                toolbarContent
            }
            .onAppear {
                prepareInitialSelectionIfNeeded()
            }
            .onChange(of: collectionItems) { _, _ in
                syncSelectionWithAvailableCollections()
            }
            .fileExporter(
                isPresented: $isExportingDocument,
                document: exportDocument,
                contentType: .zip,
                defaultFilename: "FolioraBells-export"
            ) { result in
                handleExportResult(result)
            }
            .alert("catalog.export.failed", isPresented: exportErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "")
            }
    }

    private var content: some View {
        CatalogSelectionTreeView(
            tree: selectionTree,
            selectedCollectionIDs: $selectedCollectionIDs
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            //Button("Cancel") {
            Button {
                dismiss()
            } label: {Image(systemName: "xmark")}
        }

        ToolbarItem(placement: .confirmationAction) {
            Button {
                exportSelection()
            } label: {
                if isPreparingExport {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .disabled(selectedCollectionIDs.isEmpty || isPreparingExport)
        }
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    exportErrorMessage = nil
                }
            }
        )
    }

    private static var homeFetchRequest: NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "HomeEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return request
    }

    private static var collectionFetchRequest: NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "title", ascending: true)
        ]
        return request
    }

    private var homeItems: [CatalogExportHomeItem] {
        homeEntities.compactMap(CatalogExportHomeItem.init(entity:))
    }

    private var collectionItems: [CatalogExportCollectionItem] {
        collectionEntities.compactMap(CatalogExportCollectionItem.init(entity:))
    }

    private var collectionsByHomeID: [UUID: [CatalogExportCollectionItem]] {
        Dictionary(grouping: collectionItems, by: \.homeID)
    }

    private var selectionTree: CatalogSelectionTree {
        CatalogSelectionTree(
            homes: homeItems.map { home in
                CatalogSelectionHomeItem(
                    id: home.id,
                    name: home.name,
                    iconName: home.iconName,
                    collections: collectionsByHomeID[home.id, default: []].map {
                        CatalogSelectionCollectionItem(id: $0.id, title: $0.title)
                    }
                )
            }
        )
    }

    private func prepareInitialSelectionIfNeeded() {
        guard !didPrepareInitialSelection else {
            return
        }

        selectedCollectionIDs = selectionTree.allCollectionIDs
        didPrepareInitialSelection = true
    }

    private func syncSelectionWithAvailableCollections() {
        prepareInitialSelectionIfNeeded()
        selectedCollectionIDs.formIntersection(selectionTree.allCollectionIDs)
    }

    private func exportSelection() {
        isPreparingExport = true
        exportErrorMessage = nil

        let selection: CatalogExportSelection = .collections(selectedCollectionIDs)

        Task {
            do {
                let data = try await CatalogJSONPort.exportArchiveData(
                    context: managedObjectContext,
                    selection: selection
                )

                await MainActor.run {
                    exportDocument = CatalogTransferDocument(data: data)
                    isExportingDocument = true
                    isPreparingExport = false
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    isPreparingExport = false
                }
            }
        }
    }

    private func handleExportResult(_ result: Result<URL, any Error>) {
        switch result {
        case .success:
            dismiss()
        case .failure(let error):
            exportErrorMessage = error.localizedDescription
        }
    }
}

struct CatalogImportView: View {
    @Environment(\.dismiss) private var dismiss

    let bundle: CatalogTransferBundle
    let onConfirm: (Set<CollectionID>) -> Void

    @State private var selectedCollectionIDs: Set<CollectionID>

    init(
        bundle: CatalogTransferBundle,
        onConfirm: @escaping (Set<CollectionID>) -> Void
    ) {
        self.bundle = bundle
        self.onConfirm = onConfirm
        _selectedCollectionIDs = State(initialValue: CatalogSelectionTree(bundle: bundle).allCollectionIDs)
    }

    var body: some View {
        CatalogSelectionTreeView(
            tree: selectionTree,
            selectedCollectionIDs: $selectedCollectionIDs
        )
        .navigationTitle("catalog.import.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onConfirm(selectedCollectionIDs)
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(selectedCollectionIDs.isEmpty)
            }
        }
    }

    private var selectionTree: CatalogSelectionTree {
        CatalogSelectionTree(bundle: bundle)
    }
}

private struct CatalogSelectionTreeView: View {
    let tree: CatalogSelectionTree
    @Binding var selectedCollectionIDs: Set<CollectionID>

    var body: some View {
        List {
            Section {
                selectionRow(
                    title: String(localized: "settings.importexport.catalog_title"),
                    isSelected: isCatalogSelected,
                    indentation: 0
                ) {
                    toggleCatalog()
                }

                ForEach(tree.homes) { home in
                    selectionRow(
                        title: home.name,
                        systemImage: home.iconName,
                        isSelected: isHomeSelected(home),
                        indentation: 20
                    ) {
                        toggleHome(home)
                    }

                    ForEach(home.collections) { collection in
                        selectionRow(
                            title: collection.title,
                            isSelected: selectedCollectionIDs.contains(collection.id),
                            indentation: 44
                        ) {
                            toggleCollection(collection.id)
                        }
                    }
                }
            }
        }
    }

    private var isCatalogSelected: Bool {
        !selectedCollectionIDs.isEmpty
    }

    private func isHomeSelected(_ home: CatalogSelectionHomeItem) -> Bool {
        let collectionIDs = Set(home.collections.map(\.id))
        return collectionIDs.contains { selectedCollectionIDs.contains($0) }
    }

    @ViewBuilder
    private func selectionRow(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        indentation: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.large)

                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }

                Text(title)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.leading, indentation)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleCatalog() {
        if isCatalogSelected {
            selectedCollectionIDs.removeAll()
        } else {
            selectedCollectionIDs = tree.allCollectionIDs
        }
    }

    private func toggleHome(_ home: CatalogSelectionHomeItem) {
        let collectionIDs = Set(home.collections.map(\.id))
        if isHomeSelected(home) {
            selectedCollectionIDs.subtract(collectionIDs)
        } else {
            selectedCollectionIDs.formUnion(collectionIDs)
        }
    }

    private func toggleCollection(_ collectionID: CollectionID) {
        if selectedCollectionIDs.contains(collectionID) {
            selectedCollectionIDs.remove(collectionID)
        } else {
            selectedCollectionIDs.insert(collectionID)
        }
    }
}

private struct CatalogSelectionTree: Equatable {
    let homes: [CatalogSelectionHomeItem]

    init(homes: [CatalogSelectionHomeItem]) {
        self.homes = homes
    }

    init(bundle: CatalogTransferBundle) {
        let collectionsByHomeID = Dictionary(grouping: bundle.collections, by: \.homeID)
        homes = bundle.homes
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { home in
                CatalogSelectionHomeItem(
                    id: home.id,
                    name: home.name,
                    iconName: home.iconName,
                    collections: collectionsByHomeID[home.id, default: []]
                        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                        .map { CatalogSelectionCollectionItem(id: $0.id, title: $0.title) }
                )
            }
    }

    var allCollectionIDs: Set<CollectionID> {
        Set(homes.flatMap(\.collections).map(\.id))
    }
}

private struct CatalogSelectionHomeItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let iconName: String
    let collections: [CatalogSelectionCollectionItem]
}

private struct CatalogSelectionCollectionItem: Identifiable, Hashable {
    let id: CollectionID
    let title: String
}

private struct CatalogExportHomeItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let iconName: String

    init?(entity: NSManagedObject) {
        guard let id = entity.value(forKey: "id") as? UUID else {
            return nil
        }

        self.id = id
        name = entity.value(forKey: "name") as? String ?? ""
        iconName = entity.value(forKey: "iconName") as? String ?? "house.fill"
    }
}

private struct CatalogExportCollectionItem: Identifiable, Hashable {
    let id: UUID
    let homeID: UUID
    let title: String

    init?(entity: NSManagedObject) {
        guard let id = entity.value(forKey: "id") as? UUID,
              let homeID = entity.value(forKey: "homeID") as? UUID else {
            return nil
        }

        self.id = id
        self.homeID = homeID
        title = entity.value(forKey: "title") as? String ?? ""
    }
}

#Preview {
    NavigationStack {
        CatalogExportView()
            .environment(\.managedObjectContext, CatalogExportPreviewData.context)
    }
}

#Preview("Import Selection") {
    NavigationStack {
        CatalogImportView(bundle: CatalogImportPreviewData.bundle) { _ in }
    }
}

private enum CatalogExportPreviewData {
    static let context: NSManagedObjectContext = {
        do {
            let container = try FolioraCoreDataStack.makeContainer(inMemory: true)
            let context = container.viewContext

            let firstHome = makeHome(
                id: UUID(),
                name: "Home 1",
                iconName: "house.fill",
                context: context
            )
            let secondHome = makeHome(
                id: UUID(),
                name: "Home 2",
                iconName: "building.2.fill",
                context: context
            )

            makeCollection(title: "Collection 1", home: firstHome, context: context)
            makeCollection(title: "Collection 2", home: firstHome, context: context)
            makeCollection(title: "Collection 3", home: secondHome, context: context)

            try context.save()
            return context
        } catch {
            fatalError("Failed to create CatalogExportView preview data: \(error)")
        }
    }()

    @discardableResult
    private static func makeHome(
        id: UUID,
        name: String,
        iconName: String,
        context: NSManagedObjectContext
    ) -> NSManagedObject {
        let entity = NSEntityDescription.insertNewObject(forEntityName: "HomeEntity", into: context)
        entity.setValue(id, forKey: "id")
        entity.setValue(name, forKey: "name")
        entity.setValue(iconName, forKey: "iconName")
        entity.setValue("", forKey: "notes")
        return entity
    }

    private static func makeCollection(
        title: String,
        home: NSManagedObject,
        context: NSManagedObjectContext
    ) {
        let homeID = home.value(forKey: "id") as? UUID
        let entity = NSEntityDescription.insertNewObject(forEntityName: "CollectionEntity", into: context)
        entity.setValue(UUID(), forKey: "id")
        entity.setValue(homeID, forKey: "homeID")
        entity.setValue(home.value(forKey: "name"), forKey: "homeName")
        entity.setValue(home.value(forKey: "iconName"), forKey: "homeIconName")
        entity.setValue(CollectionKind.bells.rawValue, forKey: "kindRaw")
        entity.setValue(title, forKey: "title")
        entity.setValue("", forKey: "notes")
        entity.setValue(CollectionBackgroundStyle.amber.rawValue, forKey: "backgroundStyleRaw")
        entity.setValue(home, forKey: "home")
    }
}

private enum CatalogImportPreviewData {
    static let bundle: CatalogTransferBundle = {
        let firstHomeID = UUID()
        let secondHomeID = UUID()

        return CatalogTransferBundle(
            homes: [
                Home(
                    id: firstHomeID,
                    name: "Home 1",
                    iconName: "house.fill",
                    notes: ""
                ),
                Home(
                    id: secondHomeID,
                    name: "Home 2",
                    iconName: "building.2.fill",
                    notes: ""
                )
            ],
            locations: [],
            collections: [
                Collection(
                    id: UUID(),
                    homeID: firstHomeID,
                    kind: .bells,
                    title: "Collection 1",
                    notes: ""
                ),
                Collection(
                    id: UUID(),
                    homeID: firstHomeID,
                    kind: .bells,
                    title: "Collection 2",
                    notes: ""
                ),
                Collection(
                    id: UUID(),
                    homeID: secondHomeID,
                    kind: .bells,
                    title: "Collection 3",
                    notes: ""
                )
            ],
            places: [],
            bellItems: []
        )
    }()
}
