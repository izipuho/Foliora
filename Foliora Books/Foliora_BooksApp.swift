//
//  Foliora_BooksApp.swift
//  Foliora Books
//
//  Created by Ivan Zipuho on 24.08.2026.
//

import SwiftUI
import CoreData

@main
struct Foliora_BooksApp: App {
    @State private var coreDataContainer: NSPersistentCloudKitContainer?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let coreDataContainer {
                    ContentView()
                        .environment(\.managedObjectContext, coreDataContainer.viewContext)
                } else if let startupError {
                    ContentUnavailableView(
                        "Unable to Open Library",
                        systemImage: "books.vertical",
                        description: Text(startupError)
                    )
                } else {
                    ProgressView("Preparing library")
                }
            }
            .task {
                await prepareApplicationIfNeeded()
            }
        }
    }

    @MainActor
    private func prepareApplicationIfNeeded() async {
        guard coreDataContainer == nil, startupError == nil else { return }

        do {
            coreDataContainer = try await FolioraCoreDataStack.makeContainer()
        } catch {
            startupError = error.localizedDescription
        }
    }
}
