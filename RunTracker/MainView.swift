//
//  MainView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import SwiftUI
import WeatherKit

struct MainView: View {
    var runButtonColor: Color = .blue
    var conditionMessage: String = "Condition Message"
    @State private var locationManager = LocationManager()
    @State private var currentWeather: CurrentWeather?
    
    var body: some View {
        NavigationStack{
            ZStack {
                if let weather = currentWeather {
                    Color(weather.condition.backgroundColor(isDaylight: weather.isDaylight))
                        .ignoresSafeArea()
                }
                VStack {
                    Text("App Title")
                        .font(.largeTitle)
                    NavigationLink(destination: ContentView()) {
                        Image(systemName: "figure.run")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .padding(40)
                            .background(
                                Circle().foregroundStyle(runButtonColor.gradient)
                            )
                        
                    }
                    Text(conditionMessage)
                        .font(.default)
                    
                }
                .toolbar {
                    ToolbarItem {
                        WeatherView()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
        .task(id: locationManager.userLocation) {
            guard let location = locationManager.userLocation else { return }
            currentWeather = try? await WeatherService.shared.weather(for: location, including: .current)
        }
    }
}

#Preview {
    MainView()
}
