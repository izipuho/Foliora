import SwiftUI

#if DEBUG
import CoreData
#endif

/// Displays developer-only tools and diagnostics.
struct DeveloperMenuView: View {
    @Environment(\.dismiss) private var dismiss

#if DEBUG
    @State private var cloudKitSchemaMessage: String?
    @AppStorage(RecognitionDebugSettings.artificialDelaySecondsKey)
    private var recognitionDebugDelaySeconds = 0.0
#endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        PhotoAnalysisSettingsView()
                    } label: {
                        Label("photo_analysis.title", systemImage: "photo")
                    }
                }

#if DEBUG
                Section {
                    Stepper(
                        "Analysis delay: \(Int(recognitionDebugDelaySeconds)) s",
                        value: $recognitionDebugDelaySeconds,
                        in: 0...30,
                        step: 1
                    )
                } header: {
                    Text("Recognition Debug")
                } footer: {
                    Text("Adds an artificial delay before each item-level Vision analysis batch in debug builds.")
                }

                Section("CloudKit") {
                    SettingsInfoRow(
                        title: "CloudContainer",
                        value: cloudKitContainerIdentifier
                    )

                    Button {
                        initializeCloudKitSchema()
                    } label: {
                        Label("Initialize CloudKit Schema", systemImage: "icloud.and.arrow.up")
                    }
                }
#endif
            }
            .navigationTitle("settings.developer.section_title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

#if DEBUG
    private var cloudKitContainerIdentifier: String {
        FolioraAppDelegate.coreDataContainer
            .flatMap(FolioraCoreDataStack.cloudKitContainerIdentifier)
            ?? "Unavailable"
    }

    private func initializeCloudKitSchema() {
        guard let container = FolioraAppDelegate.coreDataContainer else {
            cloudKitSchemaMessage = "Core Data container is unavailable."
            return
        }

        do {
            try container.initializeCloudKitSchema(options: [])
            cloudKitSchemaMessage = "CloudKit schema initialized successfully."
        } catch {
            cloudKitSchemaMessage = error.localizedDescription
        }
    }
#endif
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
