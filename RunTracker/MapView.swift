//
//  MapView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit

enum generationState {
    case idle
    case inProgress
    case done
}

struct MapView: View {
    @State private var locationManager = LocationManager()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var routeGenerator = RouteGenerator()
    @State private var route: GeneratedRoute?
    @State private var state: generationState = .idle
    @State private var errorMessage: String?
    @State private var isGeneratedRoute = false
    
    private let targetDistance: Double = 2000
    
    var body: some View {
        NavigationStack {
            VStack {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if let route {
                        ForEach(route.legs, id: \.self) { leg in
                            MapPolyline(leg.polyline)
                                .stroke(.blue, lineWidth: 5)
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapPitchToggle()        // Toggles between flat 2D and tilted 3D modes
                    MapScaleView()          // Shows distance/scale legend during zoom
                }
                
                if let route {
                    Text(String(format: "%.2f km", route.distanceInKm))
                        .font(.headline)
                    
                    if routeGenerator.isShowingCachedRoute {
                        Text("No new route nearby — showing an earlier one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                HStack{
                    Button{
                        createRoute()
                        isGeneratedRoute = true
                    } label: {
                        if !isGeneratedRoute {
                            Text("Rota oluştur")
                        } else {
                            if state == .inProgress {
                                ProgressView("Generating route...")
                            } else {
                                Image(systemName: "arrow.counterclockwise")
                            }
                        }
                    }
                    .disabled(state == .inProgress)
                    .padding()
                    .buttonStyle(.glassProminent)
                    
                    if isGeneratedRoute {
                        Button {
                            //start navigation route
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
        }
        .onAppear {
            if let location = locationManager.userLocation {
                cameraPosition = .region(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 750, longitudinalMeters: 750))
            }
        }
    }
    
    private func createRoute() {
        guard let location = locationManager.userLocation else { return }
        
        Task {
            state = .inProgress
            errorMessage = nil
            do {
                let newRoute = try await routeGenerator.generateLoop(
                    from: location.coordinate,
                    targetDistanceMeters: targetDistance
                )
                route = newRoute
                focus(on: newRoute)
                state = .done
            } catch {
                errorMessage = "Couldn't build a route here right now — try again in a moment."
                state = .idle
            }
        }
    }
    
    /// Kamerayı rotanın tamamını kapsayacak şekilde ayarlar.
    private func focus(on route: GeneratedRoute) {
        guard var rect = route.polylines.first?.boundingMapRect else { return }
        for polyline in route.polylines.dropFirst() {
            rect = rect.union(polyline.boundingMapRect)
        }
        cameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15))
    }
}

#Preview {
    MapView()
}
