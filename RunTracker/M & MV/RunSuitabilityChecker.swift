//
//  RunAvailibilityChecker.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import Foundation
import WeatherKit
import CoreLocation
import SwiftUI

enum RunSuitability {
    case suitable
    case nighttime
    case foggy
    case rainy
    case rainExpected
    case snowy
    case windy
    case tooHot
    case tooCold
    case severeWeather
    case unknown
}

extension RunSuitability {
    var message: String {
        switch self {
        case .suitable: "The weather is suitable for a run, let's go!"
        case .nighttime: "It's dark outside — pick a well-lit route and wear reflective gear!"
        case .foggy: "It's foggy and visibility is low, be careful out there!"
        case .rainy: "It's raining right now, better be cautious!"
        case .rainExpected: "Rain is expected within a few hours — keep it short or bring a jacket!"
        case .snowy: "It's snowing — watch out for slippery ground!"
        case .windy: "It's very windy — expect a tougher run than usual!"
        case .tooHot: "It's too hot for a run — hydrate well or wait for cooler hours!"
        case .tooCold: "It's freezing outside — layer up or stay in!"
        case .severeWeather: "Severe weather conditions, better stay at home!"
        case .unknown: "Checking the weather..."
        }
    }

    var color: Color {
        switch self {
        case .suitable: .green
        case .nighttime: .indigo
        case .foggy: .gray
        case .rainy: .blue
        case .rainExpected: .teal
        case .snowy: .cyan
        case .windy: .mint
        case .tooHot: .orange
        case .tooCold: .blue
        case .severeWeather: .red
        case .unknown: .gray
        }
    }
}

class RunSuitabilityChecker {
    var weatherService = WeatherService.shared

    func isRunSuitable(for location: CLLocation) async throws -> RunSuitability {
        let weather = try await WeatherService.shared.weather(
            for: location,
            including: .current, .hourly
        )
        let (current, hourly) = weather

        let forecastWindow = hourly.forecast.filter {
            $0.date >= Date() && $0.date <= Date().addingTimeInterval(3 * 60 * 60)
        }

        let apparentCelsius = current.apparentTemperature.converted(to: .celsius).value
        let rainNowMMPerHour = current.precipitationIntensity.converted(to: .millimetersPerHour).value
        let windKMPerHour = current.wind.speed.converted(to: .kilometersPerHour).value

        // Checks are ordered by severity: the first match is the most important
        // thing the runner should know about.
        if current.condition.isSevere || forecastWindow.contains(where: { $0.condition.isSevere }) {
            return .severeWeather
        }
        if current.condition == .hot || apparentCelsius >= 32 {
            return .tooHot
        }
        if current.condition == .frigid || apparentCelsius <= -5 {
            return .tooCold
        }
        if current.condition.isSnowy {
            return .snowy
        }
        if current.condition.isRainy || rainNowMMPerHour > 0.1 {
            return .rainy
        }
        if forecastWindow.contains(where: { $0.condition.isRainy || $0.precipitationChance >= 0.4 }) {
            return .rainExpected
        }
        if current.condition.isFoggy {
            return .foggy
        }
        if current.condition == .windy || windKMPerHour >= 30 {
            return .windy
        }
        if !current.isDaylight {
            return .nighttime
        }
        return .suitable
    }
}
