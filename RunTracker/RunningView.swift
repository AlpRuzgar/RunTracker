//
//  HomeView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import SwiftUI
import WeatherKit

struct RunningView: View {
    @State private var locationManager = LocationManager()
    @State private var runSC = RunSuitabilityChecker()
    @State private var currentWeather: CurrentWeather?
    @State private var runSuitability: RunSuitability = .unknown
    
    var body: some View {
        NavigationStack {
            ZStack {
                if let weather = currentWeather {
                    Rectangle()
                        .fill(weather.condition.backgroundColor(isDaylight: weather.isDaylight).gradient)
                        .ignoresSafeArea()
                }
                VStack {
                    Text(runSuitability.message)
                        .font(.body)
                    
                        .task(id: locationManager.userLocation) {
                            guard let location = locationManager.userLocation else { return }
                            currentWeather = try? await WeatherService.shared.weather(for: location, including: .current)
                            runSuitability = try! await runSC.isRunSuitable(for: location)
                        }
                }
                .toolbar {
                    ToolbarItem {
                        WeatherView()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
    }
}
#Preview {
    RunningView()
}
