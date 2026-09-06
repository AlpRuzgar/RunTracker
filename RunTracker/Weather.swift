//
//  Weather.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import Foundation
import WeatherKit
import SwiftUI

extension WeatherCondition {
    func backgroundColor(isDaylight: Bool) -> Color {
        switch self {
        case .clear, .mostlyClear, .partlyCloudy, .breezy, .sunFlurries, .sunShowers:
            return isDaylight ? Color(red: 0.4, green: 0.7, blue: 0.95) : Color(red: 0.05, green: 0.08, blue: 0.25)

        case .mostlyCloudy, .cloudy, .foggy, .haze, .smoky, .blowingDust:
            return isDaylight ? Color(white: 0.75) : Color(white: 0.2)

        case .drizzle, .rain, .heavyRain, .sleet, .freezingDrizzle, .freezingRain, .wintryMix, .hail:
            return isDaylight ? Color(red: 0.5, green: 0.55, blue: 0.6) : Color(red: 0.15, green: 0.17, blue: 0.2)

        case .flurries, .snow, .heavySnow, .blowingSnow, .blizzard, .frigid:
            return isDaylight ? Color(white: 0.9) : Color(red: 0.2, green: 0.22, blue: 0.3)

        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .hurricane, .tropicalStorm:
            return Color(red: 0.15, green: 0.15, blue: 0.2)

        case .windy, .hot:
            return isDaylight ? Color(red: 0.6, green: 0.75, blue: 0.9) : Color(red: 0.1, green: 0.12, blue: 0.28)

        @unknown default:
            return isDaylight ? Color(white: 0.7) : Color(white: 0.15)
        }
    }
}

extension UnitSpeed {
    // Foundation has no built-in mm/h; base unit is m/s (1 mm/h = 1/3,600,000 m/s)
    static let millimetersPerHour = UnitSpeed(symbol: "mm/h", converter: UnitConverterLinear(coefficient: 1.0 / 3_600_000))
}

extension WeatherCondition {
    var runSuitability: RunSuitability {
        switch self {
        case .clear, .mostlyClear, .partlyCloudy, .mostlyCloudy,
             .cloudy, .breezy, .sunFlurries, .sunShowers:
            return .suitable

        case .foggy, .haze, .windy, .drizzle, .rain,
             .flurries, .snow, .hot, .frigid, .wintryMix:
            return .moderate

        case .smoky, .blowingDust, .heavyRain, .heavySnow, .blowingSnow,
             .sleet, .freezingDrizzle, .freezingRain, .hail,
             .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .hurricane, .tropicalStorm, .blizzard:
            return .notSuitable

        @unknown default:
            return .moderate
        }
    }
}

extension RunSuitability {
    var points: Int {
        switch self {
        case .suitable: return 2
        case .moderate: return 1
        case .notSuitable: return 0
        }
    }
}

