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

    @State private var locationManager = LocationManager()
    @State private var routeGenerator = RouteGenerator()
    @State private var currentWeather: CurrentWeather?
    @State var timeOfDayMessage: String = "Ready to get moving?"
    @State var textColor: Color = .white
    @State private var generatedRoute: GeneratedRoute?
    @State private var isGeneratingRoute = false
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
                        quickGenerateCard()
                    } else {
                        Text("Can't find your location")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    if user.sessions.count >= 3 {
                        List {
                            ForEach(0..<3) { i in
                                RunSessionRow(session: user.sessions[i])
                            }
                        }
                    } else if user.sessions.isEmpty {
                        Text("No sessions yet!")
                    } else {
                        List(user.sessions) { session in
                            RunSessionRow(session: session)
                        }
                    }
                    
                }
                .padding()
            }
            .background(LinearGradient(colors: [.emerald, .emerald.opacity(0.1)], startPoint: .bottomTrailing, endPoint: .topLeading))
            .navigationTitle("\(timeOfDayMessage), \(user.name)!")
        }
        .task(id: locationManager.userLocation == nil) {
            timeOfDayMessage = getTimeOfDayGreeting()
            guard currentWeather == nil,
                  let location = locationManager.userLocation,
                  let current = try? await WeatherService.shared.weather(for: location, including: .current) else { return }
            withAnimation(.spring(duration: 0.7)) {
                currentWeather = current
                textColor = current.isDaylight ? .black : .white
                generateRoute()
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
    func quickGenerateCard() -> some View {
        HStack {
            if let generatedRoute {
                Map(position: $cameraPosition) {
                    ForEach(generatedRoute.polylines, id: \.self) { polyline in
                        MapPolyline(polyline)
                            .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
                .mapControlVisibility(.hidden)
                .allowsHitTesting(false) 
                .frame(width: 120, height: 120)
                VStack{
                    Text("Quick Route")
                        .font(.title)
                    Text("\(generatedRoute.distanceMeasurement.formatted())")
                        .font(.caption)
                }
                Spacer()
                NavigationLink(destination: NavigationView(route: generatedRoute)){
                    Image(systemName: "arrow.up")
                }
                .padding()
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .background(.emerald.gradient)
                .padding()
            } else {
                ProgressView()
                Text("Generating")
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .background(colorScheme == .dark ? .steelGray : .white)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 5)
    }

    func generateRoute() {
        guard let location = locationManager.userLocation else { return }
        isGeneratingRoute = true
        Task {
            defer { isGeneratingRoute = false }
            generatedRoute = try? await routeGenerator.generate(from: location.coordinate, targetDistance: user.targetDistance * 1000)
            if let generatedRoute {
                cameraPosition = .camera(.init(centerCoordinate: generatedRoute.start, distance: generatedRoute.distance))
            }
        }
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
}
