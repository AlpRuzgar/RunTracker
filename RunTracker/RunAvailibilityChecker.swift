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
    case moderate
    case notSuitable
}


class RunAvailibilityChecker {
    var weatherService = WeatherService.shared
    let message = ""
    let color: Color = .white
            
    func isRunAvailable(for location: CLLocation) async throws -> RunSuitability {
        let weather = try await WeatherService.shared.weather(
            for: location,
            including: .current, .hourly
        )
        let (current, hourly) = weather
        
        let forecastWindow = hourly.forecast.filter {
            $0.date >= Date() && $0.date <= Date().addingTimeInterval(3 * 60 * 60)
        }
        
        // HourWeather has no precipitationIntensity; its precipitationAmount over
        // one hour is equivalent to intensity in mm/h, so normalize both to Double.
        let samples: [(condition: WeatherCondition, precipitationMMPerHour: Double, isDaylight: Bool)] =
        [(current.condition, current.precipitationIntensity.converted(to: .millimetersPerHour).value, current.isDaylight)]
        + forecastWindow.map { ($0.condition, $0.precipitationAmount.converted(to: .millimeters).value, $0.isDaylight) }
        
        var totalScore = 0
        for sample in samples {
            totalScore += sample.condition.runSuitability.points
            totalScore += precipitationPoints(sample.precipitationMMPerHour)
            totalScore += sample.isDaylight ? 1 : 0
        }
        
        let averageScore = Double(totalScore) / Double(samples.count)
        
        switch averageScore {
        case ..<1.5: return .notSuitable
        case ..<3.0: return .moderate
        default: return .suitable
        }
    }
    
    private func precipitationPoints(_ mmPerHour: Double) -> Int {
        switch mmPerHour {
        case 0: return 2
        case ..<2.5: return 1   // hafif
        default: return 0        // orta/şiddetli
        }
    }
}
