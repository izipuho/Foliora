import CoreData
import SwiftUI
import UIKit

/// Displays developer-only tools and diagnostics.
struct DeveloperMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isEraseConfirmationPresented = false
    @State private var eraseState = EraseState.idle

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

                Section {
                    Button(role: .destructive) {
                        isEraseConfirmationPresented = true
                    } label: {
                        HStack {
                            Label("settings.developer.erase_icloud.button", systemImage: "icloud.slash")
                            Spacer()
                            if eraseState == .erasing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(eraseState != .idle)
                } footer: {
                    Text("settings.developer.erase_icloud.footer")
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
                    .disabled(eraseState == .erasing || eraseState == .erased)
                }
            }
            .confirmationDialog(
                "settings.developer.erase_icloud.confirm.title",
                isPresented: $isEraseConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("settings.developer.erase_icloud.confirm.action", role: .destructive) {
                    eraseAccountData()
                }
            } message: {
                Text("settings.developer.erase_icloud.confirm.message")
            }
            .alert(
                "settings.developer.erase_icloud.done.title",
                isPresented: Binding(get: { eraseState == .erased }, set: { _ in })
            ) {
                // The app has no stores left, so there is nothing to return to.
            } message: {
                Text("settings.developer.erase_icloud.done.message")
            }
            .alert(
                "settings.developer.erase_icloud.failed.title",
                isPresented: Binding(
                    get: { eraseFailureMessage != nil },
                    set: { if !$0 { eraseState = .idle } }
                )
            ) {
                Button("common.copy") {
                    UIPasteboard.general.string = eraseFailureMessage
                }
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(eraseFailureMessage ?? "")
            }
        }
        // Once the stores are gone, the rest of the app cannot work until relaunch.
        .interactiveDismissDisabled(eraseState == .erasing || eraseState == .erased)
    }

    private var eraseFailureMessage: String? {
        guard case .failed(let message) = eraseState else { return nil }
        return message
    }

    private func eraseAccountData() {
        guard let container = FolioraAppDelegate.coreDataContainer else { return }

        eraseState = .erasing
        Task {
            do {
                try await FolioraCoreDataStack.eraseAccountData(in: container)
                eraseState = .erased
            } catch {
                // The stores may already be detached; a retry erases what is left.
                eraseState = .failed(CloudKitErrorSummary.text(for: error))
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

/// Progress of erasing the account's data from the developer menu.
private enum EraseState: Equatable {
    case idle
    case erasing
    case erased
    case failed(String)
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
