//
//  ContentView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 31.08.2026.
//

import SwiftUI
import MapKit
import CoreLocation
import WeatherKit

struct ContentView: View {
    @State private var locationManager = LocationManager()
    @State private var routevm = RouteViewModel()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var routeGenerator = RouteGeneratorViewModel()
    @State private var navigator = RunNavigationViewModel()
    @State private var runStore = RunStore()
    @State private var showNavigation = false
    
    @State private var currentWeather: CurrentWeather?
    
    var body: some View {
        NavigationStack {
            VStack {
                WeatherView()
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    
                    ForEach(Array(locationManager.pathSegments.enumerated()), id: \.offset) { _, segment in
                        if segment.count > 1 {
                            MapPolyline(coordinates: catmullRomSmoothed(segment))
                                .stroke(.red, lineWidth: 4)
                        }
                    }
                    
                    if let generated = routeGenerator.generatedRoute {
                        MapPolyline(coordinates: generated)
                            .stroke(routeGenerator.generatedRoute == navigator.selectedRoute ? .blue : .green, lineWidth: 5)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onAppear() {
                    locationManager.requestPermission()
                }
                HStack {
                    VStack {
                        Button(locationManager.isTracking ? "Koşuyu bitir" : "Koşuyu başlat") {
                            if locationManager.isTracking {
                                locationManager.stopTracking()
                            } else {
                                locationManager.startTracking()
                            }
                        }
                        if locationManager.isTracking {
                            Button(locationManager.isManuallyPaused ? "DEVAM ET" : "DURAKSAT") {
                                locationManager.togglePause()
                            }
                        }
                        
                    }
                    if routeGenerator.isGenerating {
                        ProgressView("Rota oluşturuluyor...")
                    } else {
                        VStack {
                            Button("Rota oluştur") {
                                Task {
                                    guard let userLocation = locationManager.userLocationCoordinate2D else { return }
                                    await routeGenerator.generateLoopRoute(around: userLocation, targetRadius: 500)
                                }
                            }
                            if let generated = routeGenerator.generatedRoute {
                                Text(String(format: "Rota: %.2f km", routeGenerator.generatedRouteDistance / 1000))
                                    .font(.subheadline)
                                Button(navigator.selectedRoute == generated ? "Rota seçildi ✓" : "Bu rotayı seç") {
                                    navigator.selectRoute(generated)
                                }
                            }
                            if navigator.selectedRoute != nil {
                                Button("Navigasyonu başlat") {
                                    navigator.start()
                                    showNavigation = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    
                }
            }
            .padding()
            .toolbar {
                NavigationLink("Koşularım") {
                    RunsListView(runStore: runStore)
                }
            }
            .fullScreenCover(isPresented: $showNavigation) {
                RunNavigationView(locationManager: locationManager, navigator: navigator, runStore: runStore)
            }
        }
    }
    
    func catmullRomSmoothed(_ points: [CLLocationCoordinate2D], segments: Int = 8) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        
        var result: [CLLocationCoordinate2D] = []
        
        for i in 0..<points.count - 1 {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            
            for t in stride(from: 0.0, to: 1.0, by: 1.0 / Double(segments)) {
                let lat = catmullRomInterpolate(t: t, p0: p0.latitude, p1: p1.latitude, p2: p2.latitude, p3: p3.latitude)
                let lon = catmullRomInterpolate(t: t, p0: p0.longitude, p1: p1.longitude, p2: p2.longitude, p3: p3.longitude)
                result.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        
        result.append(points.last!)
        return result
    }
    
    private func catmullRomInterpolate(t: Double, p0: Double, p1: Double, p2: Double, p3: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        
        return 0.5 * (
            (2 * p1) +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}


#Preview {
    ContentView()
}
