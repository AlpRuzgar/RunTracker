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

        return district.isEmpty ? city : "\(district), \(city)"
    }
}

/// Hava kartı: uygulamanın tek renkli yüzeyi.
///
/// `lightBlue` burada da yaşar — ikincil rengin en doğal bağlamı gökyüzü.
/// Gündüz mavi berrak beyaza açılır (gündüz gökyüzü hissi); gece `midnight`e iner.
///
/// Yazı rengi zemine göre seçilir: gündüz açık mavinin üstünde beyaz yazı
/// 2:1'lik kontrastla okunmaz, koyu yazı 7:1'e çıkar (bkz. `Color.onAccent`).
struct ForecastView: View {
    let location: CLLocation
    @State private var currentWeather: CurrentWeather?
    @State private var hourlyForecast: Forecast<HourWeather>?
    @State private var district = ""

    private var isDay: Bool { currentWeather?.isDaylight ?? true }

    private var background: LinearGradient {
        LinearGradient(
            colors: isDay ? [.lightBlue, .white] : [.midnight, .steelGray],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var ink: Color { isDay ? .onAccent : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let currentWeather {
                current(currentWeather)
                if let hourlyForecast {
                    hourly(hourlyForecast)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(ink)
                    Text("Fetching forecast…")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
        .foregroundStyle(ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .animation(.smooth(duration: 0.5), value: currentWeather?.date)
        .task {
            async let current = try? WeatherService.shared.weather(for: location, including: .current)
            async let hourly = try? WeatherService.shared.weather(for: location, including: .hourly)
            async let city = try? location.getCityDistrict()

            let (c, h, n) = await (current, hourly, city)
            currentWeather = c
            hourlyForecast = h
            district = n ?? ""
        }
    }

    // MARK: - Şu an

    private func current(_ weather: CurrentWeather) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if !district.isEmpty {
                        Text(district)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .opacity(0.8)
                    }
                    Text(weather.temperature.formatted(Self.temperatureFormat))
                        .font(.display(46, weight: .bold))
                        .contentTransition(.numericText())
                    Text(weather.condition.description)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                    Text("Feels like \(weather.apparentTemperature.formatted(Self.temperatureFormat))")
                        .font(.footnote)
                        .opacity(0.8)
                }

                Spacer()

                Image(systemName: weather.symbolName)
                    .symbolVariant(.fill)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 46))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            }

            HStack(spacing: 8) {
                metric("wind", "Wind", "\(weather.wind.speed.formatted(Self.shortFormat)) \(weather.wind.compassDirection.abbreviation)")
                metric("sun.max.fill", "UV", "\(weather.uvIndex.value)")
                metric("humidity.fill", "Humidity", weather.humidity.formatted(.percent.precision(.fractionLength(0))))
            }
        }
    }

    /// Tek bir ölçüm kutusu. Cam yerine düz, yarı saydam bir dolgu: cam etkisi
    /// yalnızca haritanın üstünde kullanılır (bkz. `Theme.swift`).
    private func metric(_ symbol: String, _ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            (isDay ? Color.white.opacity(0.28) : Color.white.opacity(0.10)),
            in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous)
        )
    }

    // MARK: - Saatlik

    private func hourly(_ forecast: Forecast<HourWeather>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(ink.opacity(0.2))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(forecast.prefix(12)), id: \.date) { hour in
                        VStack(spacing: 7) {
                            Text(hour.date, format: .dateTime.hour())
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .opacity(0.8)
                            Image(systemName: hour.symbolName)
                                .symbolVariant(.fill)
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 20))
                            Text(hour.temperature.formatted(Self.temperatureFormat))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.35)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private static let temperatureFormat: Measurement<UnitTemperature>.FormatStyle =
        .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))

    private static let shortFormat: Measurement<UnitSpeed>.FormatStyle =
        .measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))
}

#Preview {
    ForecastView(location: CLLocation(latitude: 41, longitude: 28))
        .padding()
        .background(Color.canvas)
}
