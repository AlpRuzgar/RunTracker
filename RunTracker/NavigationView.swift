//
//  NavigationView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit
import SwiftData

/// Üretilmiş bir döngü rotasında adım adım navigasyon ekranı: sıradaki manevrayı
/// üstte, kalan mesafeyi ve ilerlemeyi altta gösterir. Rota takibi ve yeniden
/// rota `NavigationViewModel`'dedir; bu görünüm yalnızca konumları iletir.
///
/// Koşu boyunca kullanıcının geçtiği yol kaydedilir; "End route" bu yolu bir
/// `RunSession` olarak saklar.
struct NavigationView: View {
    /// Takip edilecek rota — MapView'da üretilen son rota.
    let route: GeneratedRoute

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var locationManager = LocationManager()
    @State private var navigation = NavigationViewModel()
    @State private var camera = RunCamera()
    /// Haritanın kuzeye göre dönüklüğü; oklar buna göre hizalanır.
    @State private var mapHeading = 0.0
    @State private var startedAt = Date.now

    var body: some View {
        Map(position: $camera.position) {
            UserAnnotation()
            // Yeniden rota sonrası çizgiler değiştiği için rota değil,
            // view model'in güncel çizgileri çizilir.
            ForEach(navigation.polylines, id: \.self) { polyline in
                MapPolyline(polyline)
                    .stroke(.blue, lineWidth: 5)
            }
            // Döngü rotasında çizgi tek başına hangi yöne koşulacağını
            // göstermez; yönü oklar taşır.
            RouteDirectionArrows(arrows: navigation.arrows, mapHeading: mapHeading)
            // Gerçekte koşulan yol, planlanan rotanın üstünde ayrı renkte.
            RunRouteOverlay(segments: locationManager.pathSegments)
        }
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
        }
        .mapControls {
            MapUserLocationButton()
            MapPitchToggle()        // Toggles between flat 2D and tilted 3D modes
            MapScaleView()          // Shows distance/scale legend during zoom
        }
        .safeAreaInset(edge: .top) {
            instructionBanner
        }
        .safeAreaInset(edge: .bottom) {
            statsBar
        }
        .onAppear {
            navigation.start(route: route)
            startedAt = .now
            locationManager.startTracking()
        }
        .onDisappear {
            navigation.stop()
            locationManager.stopTracking()
        }
        .onChange(of: locationManager.userLocation) { _, newLocation in
            guard let newLocation else { return }
            navigation.update(location: newLocation)
            camera.follow(location: newLocation, heading: locationManager.travelDirection)
        }
        .onChange(of: locationManager.userHeading) { _, _ in
            // Kullanıcı dururken dönerse harita yine de onunla dönsün.
            camera.follow(location: locationManager.userLocation, heading: locationManager.travelDirection)
        }
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Sıradaki manevrayı ya da navigasyonun genel durumunu gösteren üst şerit.
    private var instructionBanner: some View {
        VStack(spacing: 4) {
            switch navigation.state {
            case .rerouting:
                Label("Rerouting…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
            case .finished:
                Label("Loop completed!", systemImage: "flag.checkered")
                    .font(.headline)
            default:
                Text(navigation.currentInstruction)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(formatted(meters: navigation.distanceToNextManeuver))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial)
    }

    /// Kalan mesafe, ilerleme çubuğu ve koşuyu bitirme düğmesini taşıyan alt şerit.
    private var statsBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: navigation.progressFraction)

            HStack {
                VStack(alignment: .leading) {
                    Text("\(formatted(meters: navigation.remainingDistance)) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(startedAt, style: .timer)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
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
                    Label("End route", systemImage: "stop.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
            }
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
            segments: locationManager.pathSegments,
            plannedDistance: route.distance
        )
        let path = TraveledPath(
            name: "Route run — \(startedAt.formatted(date: .abbreviated, time: .shortened))",
            segments: session.segments
        )
        session.traveledPath = path
        modelContext.insert(session)
        navigation.stop()
        dismiss()
    }

    /// Mesafeyi kullanıcı dostu yazar: 1 km altında metre, üstünde km.
    private func formatted(meters: Double) -> String {
        meters < 1000
            ? String(format: "%.0f m", meters)
            : String(format: "%.2f km", meters / 1000)
    }
}
