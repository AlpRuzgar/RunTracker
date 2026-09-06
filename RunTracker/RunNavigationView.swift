//
//  RunNavigationView.swift
//  RunTracker
//

import SwiftUI
import MapKit

struct RunNavigationView: View {
    @Environment(\.dismiss) private var dismiss

    let locationManager: LocationManager
    let navigator: RunNavigationViewModel
    let runStore: RunStore

    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()

                if let route = navigator.selectedRoute, route.count > 1 {
                    MapPolyline(coordinates: route)
                        .stroke(.blue, lineWidth: 5)
                }
                if navigator.traveledPath.count > 1 {
                    MapPolyline(coordinates: navigator.traveledPath)
                        .stroke(.red, lineWidth: 4)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }

            // Yön talimatı
            if !navigator.instruction.isEmpty {
                Text(navigator.instruction)
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            controlBar
        }
        .onChange(of: locationManager.userLocationCoordinate2D) { _, newLocation in
            guard let newLocation else { return }
            Task {
                await navigator.update(with: newLocation)
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 12) {
            HStack {
                stat("Süre") {
                    // Kronometrenin saniyede bir yenilenmesi için
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(formattedDuration(navigator.elapsedTime))
                    }
                }
                Spacer()
                stat("Mesafe") {
                    Text(String(format: "%.2f km", navigator.traveledDistance / 1000))
                }
                Spacer()
                stat("Kalan") {
                    Text(String(format: "%.2f km", navigator.remainingDistance / 1000))
                }
            }

            HStack(spacing: 16) {
                Button(navigator.state == .paused ? "Devam et" : "Duraklat") {
                    navigator.togglePause()
                }
                .buttonStyle(.bordered)

                Button("Bitir", role: .destructive) {
                    if let run = navigator.stop() {
                        runStore.add(run)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private func stat(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            value()
                .font(.title3)
                .monospacedDigit()
        }
    }
}
