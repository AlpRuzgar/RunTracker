//
//  NavigationView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit

struct NavigationView: View {
    @State private var locationManager = LocationManager()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var routeGenerator = RouteGenerator()
    @State private var route: GeneratedRoute?

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
            }
        }
    }
}

#Preview {
    NavigationView()
}
