//
//  RunTrackerApp.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 31.08.2026.
//

import SwiftUI
import FirebaseCore
import SwiftData

@main
struct RunTrackerApp: App {
    var body: some Scene {
        WindowGroup {
                MainView()
        }
        .modelContainer(for: [RunSession.self, TraveledPath.self])
    }
}
