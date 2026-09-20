//
//  RunTrackerApp.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 31.08.2026.
//

import SwiftUI
import SwiftData

@main
struct RunTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [RunSession.self, TraveledPath.self, User.self])
    }
}

/// Henüz kullanıcı oluşturulmamışsa (ilk açılış) onboarding anketini,
/// aksi halde uygulamanın ana ekranını gösterir. Oluşturulan kullanıcı
/// alt görünümlere environment üzerinden verilir.
private struct RootView: View {
    @Query private var users: [User]

    var body: some View {
        if let user = users.first {
            MainView()
                .environment(user)
        } else {
            UserQAView()
        }
    }
}
