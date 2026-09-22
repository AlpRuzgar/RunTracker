//
//  RunSessionDetailView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit

struct RunSessionDetailView: View {
    let session: RunSession
    /// Haritanın kuzeye göre dönüklüğü; oklar buna göre hizalanır.
    @State private var mapHeading = 0.0
    /// Yön okları kamera her oynadığında yeniden hesaplanmasın diye saklanır.
    @State private var arrows: [RouteArrow] = []
    @State private var isNavigating = false
    @State private var district: String?

    private var isRoute: Bool { session.plannedDistance != nil }
    private var tint: Color { isRoute ? .emerald : .brightOrange }

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.stack) {
                mapHero
                summary
                if let path = session.traveledPath {
                    runAgainButton(path: path)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .navigationTitle(district ?? "Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let path = session.traveledPath {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        path.isFavorite.toggle()
                    } label: {
                        Image(systemName: path.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(path.isFavorite ? Color.brightOrange : Color.secondary)
                    }
                    .accessibilityLabel(path.isFavorite ? "Remove from favorites" : "Add to favorites")
                }
            }
        }
        .task {
            district = (try? await session.district) ?? "Run"
            arrows = RouteArrow.along(session.segments.polylines)
        }
    }

    // MARK: - Harita

    private var mapHero: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom, .rotate]) {
            RouteOverlay(
                polylines: session.segments.polylines,
                tint: tint,
                mapHeading: mapHeading,
                arrows: arrows
            )
        }
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
        }
        .mapControlVisibility(.hidden)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            // Koşunun türü haritanın üstünde durur: rota mı serbest koşu mu
            // olduğu, çizginin rengiyle birlikte ilk bakışta anlaşılsın.
            Label(isRoute ? "Route run" : "Free run", systemImage: isRoute ? "map.fill" : "figure.run")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint, in: .capsule)
                .padding(12)
        }
    }

    // MARK: - Özet

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.distanceInKm.formatted(.number.precision(.fractionLength(2))))
                    .font(.display(40, weight: .bold))
                Text("km")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider().overlay(Color.hairline)

            HStack(alignment: .top, spacing: 8) {
                StatView(title: "Time", stat: session.duration.mmss)
                StatView(title: "Pace", stat: session.pace?.mmss ?? "—")
                if let planned = session.plannedDistance {
                    StatView(
                        title: "Planned",
                        stat: Measurement(value: planned, unit: UnitLength.meters)
                            .converted(to: .kilometers)
                            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                                    numberFormatStyle: .number.precision(.fractionLength(2))))
                    )
                }
            }
        }
        .card()
    }

    private func runAgainButton(path: TraveledPath) -> some View {
        // Navigasyon tam ekran açılır; gezinme çubuğuyla itilen bir sayfa
        // değil, kendi başına bir ekrandır.
        Button {
            isNavigating = true
        } label: {
            Label("Run this path again", systemImage: "arrow.trianglehead.counterclockwise")
        }
        .buttonStyle(PrimaryButtonStyle())
        .fullScreenCover(isPresented: $isNavigating) {
            NavigationView(route: path)
        }
    }
}
