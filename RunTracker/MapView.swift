//
//  MapView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit

struct MapView: View {
    @State private var locationManager = LocationManager()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var routeVM = RouteViewModel()
    @State private var routeGenerator = RouteGeneratorViewModel()
    var body: some View {
        NavigationStack {
            VStack {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapPitchToggle()        // Toggles between flat 2D and tilted 3D modes
                    MapScaleView()          // Shows distance/scale legend during zoom
                }
                Button("Create Route") {
                    if let location = locationManager.userLocation {
                        Task {
                            print("Rota oluşturulma çağrısı yapıldı")
                            await routeGenerator.generateLoopRoute(around: location.coordinate, targetRadius: 500)
                        }
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
}

#Preview {
    MapView()
}
