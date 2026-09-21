//
//  HomeView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import SwiftUI
import WeatherKit
import SwiftData
import MapKit

struct HomeView: View {
    @Environment(User.self) private var user
    @Environment(\.colorScheme) private var colorScheme

    /// Uygulama genelinde paylaşılan tek üretim motoru (bkz. `RunTrackerApp`).
    /// Ana ekranın kendi motoru vardı: MapKit kotasını Run sekmesinden habersiz
    /// harcıyor, öğrendiği dolambaç katsayısını saklamıyor ve ürettiği rotayı
    /// Run sekmesiyle paylaşmıyordu.
    @Environment(RouteViewModel.self) private var routes
    @State private var locationManager = LocationManager()
    @State private var currentWeather: CurrentWeather?
    @State var timeOfDayMessage: String = "Ready to get moving?"
    @State var textColor: Color = .white
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    @Query private var currentWeekSessions: [RunSession]
    
    init() {
        _currentWeekSessions = Query(filter: RunSession.currentWeekPredicate(),
                                     sort: \.startedAt)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView{
                VStack{
                    if let location = locationManager.userLocation {
                        ForecastView(location: location)
                        
                    } else {
                        Text("Can't find your location")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(colorScheme == .dark ? .steelGray : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .shadow(radius: 5)
                    }
                    recentRunsList()
                }
                .padding()
            }
            .background(LinearGradient(colors: [.lightBlue, .lightBlue.opacity(0.1)], startPoint: .bottomTrailing, endPoint: .topLeading))
            .navigationTitle("\(timeOfDayMessage), \(user.name)!")
        }
        .onChange(of: routes.route?.id) {
            guard let route = routes.route else { return }
            cameraPosition = .camera(.init(centerCoordinate: route.start, distance: route.distance))
        }
        .task(id: locationManager.userLocation == nil) {
            timeOfDayMessage = getTimeOfDayGreeting()
            guard let location = locationManager.userLocation else { return }

            // Rota, havadan ÖNCE ve ondan bağımsız istenir. Eskiden hava
            // çağrısının arkasındaydı: hava servisi yanıt vermediğinde kart
            // sonsuza kadar "Generating" yazıyor, rota hiç istenmiyordu.
            routes.generateIfNeeded(from: location.coordinate, targetKilometers: user.targetDistance)

            guard currentWeather == nil,
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
        case 0..<5:  return "Goodnight"
        case 5..<11: return "Good morning"
        case 11..<17: return "Good Afternoon"
        case 17..<21: return "Good Evening"
        case 21..<24: return "Goodnight"
        default:
            return "Ready to get moving?"
        }
    }
    
    @ViewBuilder
    func recentRunsList() -> some View {
        VStack {
            Text("Recent Sessions")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.title2)
                .bold()
                .padding(.bottom, 10)
            if !currentWeekSessions.isEmpty {
                List(currentWeekSessions) {session in
                    RunSessionRow(session: session)
                }
            }
            else {
                Text("No sessions this week!")
            }
        }
        .padding()
        .background(colorScheme == .dark ? .steelGray : .white)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 5)
    }
}

#Preview {
    HomeView()
        .environment(
            User(
                name: "Alp",
                sex: .male,
                bday: .now,
                heightCM: 1.8,
                weightKG: 75,
                targetDistance: 5,
                motivation: .hobby
            )
        )
        .environment(RouteViewModel())
}
