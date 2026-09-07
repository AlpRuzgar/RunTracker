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

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem{ Label("Home", systemImage: "house")}
            RunningView()
                .tabItem { Label("Run", systemImage: "figure.run") }
                .tag(Tab.run)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person")}
        }
    }
}

#Preview {
    MainView()
}
