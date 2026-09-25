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
    /// Rota üretimi uygulama genelinde TEKTİR: MapKit'in hız kotası, bacak
    /// cache'i ve "son rotalar" geçmişi tek bir yerde toplanır. Sekmeler kendi
    /// kopyalarını yarattığında kota iki katına çıkıp throttle'a giriyor,
    /// geçmişler ayrıldığı için de aynı rota iki kez üretilebiliyordu.
    @State private var routes = RouteViewModel()

    var body: some View {
        Group {
            if let user = users.first {
                MainView()
                    .environment(user)
                    .environment(routes)
            } else {
                UserQAView()
            }
        }
        // Uygulamanın birincil rengi; onboarding dahil her yerde geçerli
        // (bkz. `Theme.swift`).
        .tint(.secondaryGreen)
        // Açılışta hiçbir koşu ekranı açık değildir; kilit ekranında kalmış
        // bir koşu kartı varsa önceki oturumdan artakalandır.
        .task { await RunLiveActivity.endStaleActivities() }
    }
}
