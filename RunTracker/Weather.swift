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
    // Conditions dangerous enough that no other factor matters.
    var isSevere: Bool {
        switch self {
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .hurricane, .tropicalStorm, .blizzard,
             .heavyRain, .heavySnow, .blowingSnow, .sleet,
             .freezingDrizzle, .freezingRain, .hail,
             .smoky, .blowingDust:
            return true
        default:
            return false
        }
    }

    var isRainy: Bool {
        switch self {
        case .drizzle, .rain, .sunShowers, .wintryMix:
            return true
        default:
            return false
        }
    }

    var isSnowy: Bool {
        switch self {
        case .flurries, .snow, .sunFlurries:
            return true
        default:
            return false
        }
    }

    var isFoggy: Bool {
        switch self {
        case .foggy, .haze:
            return true
        default:
            return false
        }
    }
}

