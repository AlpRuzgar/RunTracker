//
//  WeatherView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//
import Foundation
import SwiftUI
import WeatherKit

struct WeatherView : View {
    @State var currentWeather: CurrentWeather?
    @State var locationManager = LocationManager()

    var body: some View {
        HStack {
            if let weather = currentWeather {
                HStack {
                    Image(systemName: weather.symbolName)
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 25))
                    Text(weather.temperature.formatted(
                        .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))
                    ))
                    .font(.system(size: 15, weight: .bold))
                }
                .padding(8)
                .glassEffect(.regular , in: .capsule)
            } else {
                ProgressView()
            }
        }
        .task(id: locationManager.userLocation) {
            guard let location = locationManager.userLocation else { return }
            currentWeather = try? await WeatherService.shared.weather(for: location, including: .current)
        }
    }
}

#Preview {
    WeatherView()
}
