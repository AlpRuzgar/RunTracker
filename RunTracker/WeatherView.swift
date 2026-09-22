//
//  WeatherView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//
import Foundation
import SwiftUI
import WeatherKit

/// Sıcaklığı tek satırda gösteren küçük rozet. Haritanın üstünde de
/// kullanılabildiği için zemini cam.
struct WeatherView: View {
    @State var currentWeather: CurrentWeather?
    @State var locationManager = LocationManager()

    var body: some View {
        Group {
            if let weather = currentWeather {
                HStack(spacing: 6) {
                    Image(systemName: weather.symbolName)
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 17))
                    Text(weather.temperature.formatted(
                        .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))
                    ))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
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
