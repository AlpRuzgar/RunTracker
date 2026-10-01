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
    /// Kilit ekranı ve Dynamic Island'daki koşu kartı.
    @State private var liveActivity = RunLiveActivity()

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
            RunTopBanner {
                Label("Free run", systemImage: "figure.run")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
        }
        .safeAreaInset(edge: .bottom) {
            statsBar
        }
        .runScreenLifecycle(
            locationManager: locationManager,
            camera: camera,
            liveActivity: liveActivity,
            kind: .freeRun,
            activityState: { activityState() },
            endRun: { endRun() },
            onStart: {
                startedAt = .now
                locationManager.startTracking()
            }
        )
    }

    /// Mesafe, süre ve koşuyu bitirme düğmesini taşıyan alt şerit.
    private var statsBar: some View {
        RunBottomPanel {
            HStack(alignment: .center, spacing: 14) {
                RunStat(label: "distance") {
                    Text(distanceMeasurement.formatted(
                        .measurement(width: .abbreviated, usage: .road,
                                     numberFormatStyle: .number.precision(.fractionLength(2))))
                    )
                }

                RunStatDivider()

                RunStat(
                    label: locationManager.isPaused ? "paused" : "elapsed",
                    labelColor: locationManager.isPaused ? .primaryBlue : .secondary
                ) {
                    Text(startedAt, style: .timer)
                }

                Spacer(minLength: 0)

                FollowToggle(camera: camera, tint: .primaryBlue)
            }

            Button {
                endRun()
            } label: {
                Label("End run", systemImage: "stop.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    /// Live Activity'de gösterilen koşu bilgileri.
    private func activityState(phase: RunActivityAttributes.Phase = .running) -> RunLiveActivity.State {
        RunLiveActivity.State(
            phase: phase,
            startedAt: startedAt,
            finalDuration: phase == .ended ? Date.now.timeIntervalSince(startedAt) : nil,
            distance: distance,
            secondsPerKilometer: RunLiveActivity.pace(distance: distance, since: startedAt)
        )
    }

    /// Koşuyu bitirir: geçilen yolu bir `RunSession` ve yeni bir `TraveledPath`
    /// olarak kaydedip ekranı kapatır.
    private func endRun() {
        locationManager.stopTracking()
        liveActivity.end(finalState: activityState(phase: .ended))
        RunSession.saveFinishedRun(
            startedAt: startedAt,
            segments: locationManager.pathSegments,
            pathName: "Free run",
            user: users.first,
            in: modelContext
        )
        dismiss()
    }
}

#Preview {
    FreeRunView()
        .modelContainer(for: [User.self, RunSession.self, TraveledPath.self], inMemory: true)
}
