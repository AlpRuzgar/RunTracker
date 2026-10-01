//
//  MainView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import SwiftUI
import WeatherKit

struct MainView: View {
    enum Tab { case home, run, profile }
    @State private var selectedTab: Tab = .home
    /// Ana ekran ve Run sekmesi tek bir konum kaynağını paylaşır: her biri kendi
    /// `CLLocationManager`'ını kurduğunda GPS ve pusula iki kez çalışıyordu.
    /// Koşu ekranları bunu KULLANMAZ — kendi kayıtlarını ve arka plan konum
    /// ayarlarını tutarlar.
    @State private var locationManager = LocationManager()

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            MapView()
                .tabItem { Label("Run", systemImage: "figure.run") }
                .tag(Tab.run)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(Tab.profile)
        }
        .environment(locationManager)
        // Sekme çubuğu uygulamanın birincil rengini taşır (bkz. `Theme.swift`).
        .tint(.secondaryGreen)
    }
}

#Preview {
    MainView()
        .environment(
            User(
                name: "Alp",
                sex: .male,
                bday: .now,
                heightCM: 1.8,
                weightKG: 75,
                targetDistance: 5,
                motivation: .hobby
            )
        )
        .environment(RouteViewModel())
}
