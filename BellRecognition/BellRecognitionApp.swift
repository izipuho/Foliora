//
//  BellRecognitionApp.swift
//  BellRecognition
//
//  Created by Ivan Zipuho on 04.05.2026.
//

import SwiftUI

/// Provides the bell recognition app application entry point.
@main
struct BellRecognitionApp: App {
    var body: some Scene {
        WindowGroup {
            VisionDebugView()
        }
    }
}
