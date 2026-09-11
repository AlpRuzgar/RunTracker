//
//  FreeRunView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit
import SwiftData

/// Rotasız koşu ekranı: yol tarifi yok, yalnızca kullanıcının geçtiği yol,
/// gidilen mesafe ve süre izlenir. "End run" koşuyu bir `RunSession` olarak
/// saklar.
struct FreeRunView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var locationManager = LocationManager()
    @State private var camera = RunCamera()
    @State private var startedAt = Date.now

    /// Şu ana kadar koşulan mesafe (metre).
    private var distance: Double {
        RunSession.distance(of: locationManager.pathSegments)
    }

    var body: some View {
        Map(position: $camera.position) {
            UserAnnotation()
            RunRouteOverlay(segments: locationManager.pathSegments)
        }
        .mapControls {
            MapUserLocationButton()
            MapPitchToggle()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            statsBar
        }
        .onAppear {
            startedAt = .now
            locationManager.startTracking()
        }
        .onDisappear {
            locationManager.stopTracking()
        }
        .onChange(of: locationManager.userLocation) { _, newLocation in
            camera.follow(location: newLocation, heading: locationManager.travelDirection)
        }
        .onChange(of: locationManager.userHeading) { _, _ in
            // Kullanıcı dururken dönerse harita yine de onunla dönsün.
            camera.follow(location: locationManager.userLocation, heading: locationManager.travelDirection)
        }
        .navigationTitle("Free run")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Mesafe, süre ve koşuyu bitirme düğmesini taşıyan alt şerit.
    private var statsBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.2f km", distance / 1000))
                    .font(.headline.monospacedDigit())
                Text(startedAt, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if locationManager.isPaused {
                    Text("Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Takip kapatılınca kullanıcı haritayı serbestçe inceleyebilir.
            Button {
                camera.isFollowing.toggle()
            } label: {
                Image(systemName: camera.isFollowing ? "location.fill" : "location.slash")
            }
            .buttonStyle(.glass)

            Button {
                endRun()
            } label: {
                Label("End run", systemImage: "stop.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
        }
        .padding()
        .background(.regularMaterial)
    }

    /// Koşuyu bitirir: geçilen yolu bir `RunSession` ve yeni bir `TraveledPath`
    /// olarak kaydedip ekranı kapatır.
    private func endRun() {
        locationManager.stopTracking()
        let session = RunSession(
            startedAt: startedAt,
            segments: locationManager.pathSegments
        )
        let path = TraveledPath(
            name: "Free run — \(startedAt.formatted(date: .abbreviated, time: .shortened))",
            segments: session.segments
        )
        session.traveledPath = path
        modelContext.insert(session)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        FreeRunView()
    }
}
