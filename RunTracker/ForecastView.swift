//
//  ForecastView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 14.09.2026.
//

import SwiftUI
import CoreLocation
import WeatherKit
import MapKit

extension CLLocation {
    func getCityDistrict() async throws -> String {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(self)
        
        guard let placemark = placemarks.first else {
            throw NSError(domain: "Geocoding", code: 0, userInfo: [NSLocalizedDescriptionKey: "Konum bulunamadı"])
        }
        
        // Şehir
        let city = placemark.locality ?? ""
        // İlçe / semt
        let district = placemark.subLocality ?? ""
        
        return "\(district), \(city)"
    }
}

struct ForecastView: View {
    @State var location: CLLocation
    @State private var currentWeather: CurrentWeather?
    @State private var hourlyForecast: Forecast<HourWeather>?
    @State var backgroundColors: [Color] = [.white]
    @State var hourTextColor: Color = .black
    
    @State private var district: String = ""
    
    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 16) {
                if let currentWeather {
                    CurrentWeatherView(weather: currentWeather, district: district)
                        .padding([.horizontal, .top])
                        .transition(.blurReplace.combined(with: .move(edge: .top)))
                    if let hourlyForecast {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(hourlyForecast, id: \.date) { hour in
                                    HourWeatherView(weather: hour, textColor: .white)
                                        .scrollTransition { content, phase in
                                            content
                                                .opacity(phase.isIdentity ? 1 : 0.4)
                                                .scaleEffect(phase.isIdentity ? 1 : 0.85)
                                        }
                                }
                            }
                            .padding([.horizontal, .bottom])
                        }
                        .transition(.blurReplace.combined(with: .move(edge: .bottom)))
                    }
                } else {
                    ProgressView("Fetching forecast…")
                        .padding(32)
                        .glassEffect(in: .rect(cornerRadius: 24))
                        .padding(.vertical, 40)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .light)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal)
        .task {
            let current = try? await WeatherService.shared.weather(for: location, including: .current)
            let hourly = try? await WeatherService.shared.weather(for: location, including: .hourly)
            let city = (try? await location.getCityDistrict()) ?? ""
            withAnimation(.spring(duration: 0.7)) {
                currentWeather = current
                hourlyForecast = hourly
                backgroundColors = current!.isDaylight ? [.blue, .cyan, .teal] : [.midnight.exposureAdjust(2.5), .midnight]
                hourTextColor = current!.isDaylight ? .black : .white
                district = city
            }
        }
    }
}

struct CurrentWeatherView: View {
    let weather: CurrentWeather
    let district: String
    private var temperatureFormat: Measurement<UnitTemperature>.FormatStyle {
        .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))
    }
    
    private var textColor: Color {
        weather.isDaylight ? .secondary : .primary
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(district)
                    Text(weather.date.formatted(date: .abbreviated, time: .shortened))
                    Text(weather.temperature.formatted(temperatureFormat))
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("Feels like \(weather.apparentTemperature.formatted(temperatureFormat))")
                        .font(.subheadline)
                    Text(weather.condition.description)
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Image(systemName: weather.symbolName)
                    .symbolVariant(.fill)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 56))
                    .shadow(radius: 10)
            }
            .padding(20)
            .glassEffect(.identity, in: .rect(cornerRadius: 24))

            Grid(horizontalSpacing: 15, verticalSpacing: 15) {
                GridRow {
                    WeatherMetricView(
                        symbol: "wind",
                        title: "Wind",
                        value: "\(weather.wind.speed.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))) \(weather.wind.compassDirection.abbreviation)",
                        glass: .regular,
                        symbolColor: .blue
                    )
                    WeatherMetricView(
                        symbol: "sun.max.fill",
                        title: "UV \(weather.uvIndex.value)",
                        value: weather.uvIndex.category.description,
                        glass: .regular,
                        symbolColor: .orange
                    )
                }
                GridRow {
                    WeatherMetricView(
                        symbol: "humidity.fill",
                        title: "Humidity",
                        value: weather.humidity.formatted(.percent),
                        glass: .regular,
                        symbolColor: .mint
                    )
                    WeatherMetricView(
                        symbol: "eye.fill",
                        title: "Visibility",
                        value: weather.visibility.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))),
                        glass: .regular,
                        symbolColor: .green
                    )
                }
            }
            .padding(.top, 8)
        }
    }
}

struct WeatherMetricView: View {
    let symbol: String
    let title: String
    let value: String
    let glass: Glass
    let symbolColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .foregroundStyle(symbolColor)
            VStack{
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.midnight)
                Text(value)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.midnight)

            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassEffect(glass.tint(.white.opacity(0.8)), in: .rect(cornerRadius: 18))
    }
}

struct HourWeatherView: View {
    let weather: HourWeather
    let textColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(weather.date, format: .dateTime.hour(.twoDigits(amPM: .narrow)).minute(.twoDigits))
                .font(.caption.weight(.medium))
                .foregroundStyle(textColor)
            Image(systemName: weather.symbolName)
                .symbolVariant(.fill)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 32))
                .shadow(radius: 5)
            Text(weather.temperature, format: .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
                .font(.headline)
                .foregroundStyle(textColor)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .glassEffect(.identity)
    }
}

#Preview {
    ForecastView(location: CLLocation(latitude: 41, longitude: 28))
}
