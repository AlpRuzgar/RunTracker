//
//  FavoritePathsSheet.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 22.09.2026.
//

import SwiftUI
import SwiftData
import MapKit

struct FavoritePathsSheet: View {
    @Query(filter: #Predicate<TraveledPath> { $0.isFavorite }) private var favPaths: [TraveledPath]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                ScreenHeader(title: "Favorite paths", subtitle: "Saved routes")

                if favPaths.isEmpty {
                    EmptyStateView(
                        icon: "star",
                        title: "No favorites yet",
                        message: "Star a run from its detail screen and it will show up here."
                    )
                    .card()
                } else {
                    ForEach(favPaths) { path in
                        FavRow(path: path)
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
    }
}

struct FavRow: View {
    var path: TraveledPath
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// Kayıtlı yol ters yönde mi koşulacak?
    @State private var isReversed = false
    @State private var isNavigating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Measurement(value: path.distance, unit: UnitLength.meters).formatted(
                        .measurement(width: .abbreviated, usage: .road,
                                     numberFormatStyle: .number.precision(.fractionLength(2))))
                    )
                    .font(.display(24, weight: .bold))
                    .monospacedDigit()

                    Text(path.timesUsed == 1 ? "Run once" : "Run \(path.timesUsed) times")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Map(position: $cameraPosition, interactionModes: []) {
                    RouteOverlay(polylines: displayedPath.polylines, tint: .secondaryGreen, density: .compact)
                }
                .mapControlVisibility(.hidden)
                .allowsHitTesting(false)
                .frame(width: 84, height: 84)
                .task(id: isReversed) {
                    cameraPosition = .rect(displayedPath.polylines.framingRect())
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
            }

            Picker("Direction", selection: $isReversed) {
                Text("Forward").tag(false)
                Text("Reversed").tag(true)
            }
            .pickerStyle(.segmented)

            // Navigasyon bu sayfanın İÇİNE açılmaz: sheet'e itilen bir
            // navigasyon ekranı sheet boyunda kalırdı. Tam ekran açılır.
            Button {
                isNavigating = true
            } label: {
                Label("Start navigation", systemImage: "location.north.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: .secondaryGreen))
        }
        .card()
        .fullScreenCover(isPresented: $isNavigating) {
            NavigationView(route: path, isReversed: isReversed)
        }
    }

    /// Küçük resimde gösterilen yol: ters yön seçiliyse oklar da ters dönsün
    /// diye çevrilmiş hâli çizilir.
    private var displayedPath: any FollowablePath {
        isReversed ? path.reversed() : path
    }
}

#Preview {
    FavoritePathsSheet()
        .modelContainer(for: [User.self, RunSession.self, TraveledPath.self], inMemory: true)
}
