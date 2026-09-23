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
    @Query private var users: [User]

    @State private var locationManager = LocationManager()
    @State private var camera = RunCamera()
    @State private var startedAt = Date.now

    /// Şu ana kadar koşulan mesafe (metre).
    private var distance: Double {
        RunSession.distance(of: locationManager.pathSegments)
    }

    private var distanceMeasurement: Measurement<UnitLength> {
        Measurement(value: distance, unit: .meters)
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
        .safeAreaInset(edge: .top) {
            // Serbest koşuda takip edilecek bir rota yok; üst şerit yalnızca
            // geri dönüşü ve ekranın ne olduğunu taşır.
            HStack(spacing: 12) {
                backButton
                Label("Free run", systemImage: "figure.run")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                backButton.hidden()
            }
            .padding(14)
            .glassVisual(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 6)
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
    }

    /// Ekranın tek gezinme öğesi: koşu ekranları tam ekran açılır, gezinme
    /// çubuğu taşımazlar. Koşuyu KAYDETMEZ — kaydeden düğme alttaki "End run".
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
        }
        .glassVisual(.regular, in: .circle)
        .accessibilityLabel("Back")
    }

    /// Mesafe, süre ve koşuyu bitirme düğmesini taşıyan alt şerit.
    private var statsBar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(distanceMeasurement.formatted(
                        .measurement(width: .abbreviated, usage: .road,
                                     numberFormatStyle: .number.precision(.fractionLength(2))))
                    )
                    .font(.display(24, weight: .bold))
                    .monospacedDigit()
                    Text("distance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 34).overlay(Color.primary.opacity(0.12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(startedAt, style: .timer)
                        .font(.display(24, weight: .bold))
                        .monospacedDigit()
                    Text(locationManager.isPaused ? "paused" : "elapsed")
                        .font(.caption)
                        .foregroundStyle(locationManager.isPaused ? .primaryBlue : .secondary)
                }

                Spacer(minLength: 0)

                // Takip kapatılınca kullanıcı haritayı serbestçe inceleyebilir.
                Button {
                    camera.isFollowing.toggle()
                } label: {
                    Image(systemName: camera.isFollowing ? "location.fill" : "location.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(camera.isFollowing ? .primaryBlue : .secondary)
                        .frame(width: 38, height: 38)
                }
                .glassVisual(.regular, in: .circle)
                .accessibilityLabel(camera.isFollowing ? "Stop following" : "Follow me")
            }

            Button {
                endRun()
            } label: {
                Label("End run", systemImage: "stop.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .glassVisual(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 6)
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
        session.user = users.first
        modelContext.insert(session)
        dismiss()
    }
}

#Preview {
    FreeRunView()
        .modelContainer(for: [User.self, RunSession.self, TraveledPath.self], inMemory: true)
}
