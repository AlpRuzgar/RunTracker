//
//  HomeView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import SwiftUI
import WeatherKit

struct HomeView: View {
    @State private var locationManager = LocationManager()
    @State private var currentWeather: CurrentWeather?
    @State var timeOfDayMessage: String = "Ready to get moving?"
    @State var textColor: Color = .white
    
    var body: some View {
        ZStack {
            VStack{
                Text(timeOfDayMessage)
                    .font(.system(size: 30, weight: .bold))
                    .padding(.horizontal, 2)
                    .foregroundStyle(.white)
                if let location = locationManager.userLocation {
                    ForecastView(location: location)
                }
            }
        }
        // task(id:) re-runs when the first location fix arrives, unlike onAppear
        // which fires once before CoreLocation has delivered anything.
        .task(id: locationManager.userLocation == nil) {
            timeOfDayMessage = getTimeOfDayGreeting()
            guard currentWeather == nil,
                  let location = locationManager.userLocation,
                  let current = try? await WeatherService.shared.weather(for: location, including: .current) else { return }
            withAnimation(.spring(duration: 0.7)) {
                currentWeather = current
                textColor = current.isDaylight ? .black : .white
            }
        }
        
    }
    
    func getTimeOfDayGreeting() -> String {
        // Extract the current hour component (0-23)
        let hour = Calendar.current.component(.hour, from: Date.now)
        
        switch hour {
        case 0..<5:  return "Looking for a midnight session?"
        case 5..<11: return "Good morning! Ready to get moving today?"
        case 11..<17: return "Take a break from your day, get moving!"
        case 17..<21: return "Close out your day with a good session!"
        case 21..<24: return "Moving late still counts."
        default:
            return "Ready to get moving?"
        }
    }
    
}

#Preview {
    HomeView()
}
