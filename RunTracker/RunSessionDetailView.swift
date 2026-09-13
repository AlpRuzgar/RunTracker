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
    var body: some View {
        NavigationStack {
            VStack {
                Map {
                    RunRouteOverlay(session)
                }
                Text("Mesafe: \(session.distanceInKm)")
                Text("Süre: \(session.formatted(seconds: session.duration))")
                // Kaydedilmiş yol varsa aynı yol yeniden koşulabilir.
                if let path = session.traveledPath {
                    HStack {
                        Button("", systemImage: path.isFavorite ? "star.fill" : "star") { path.isFavorite.toggle() ; print("is path favorite: \(path.isFavorite)")}
                        NavigationLink(destination: NavigationView(route: path)) {
                            Label("Run this path again", systemImage: "arrow.trianglehead.counterclockwise")
                        }
                    }
                }
            }
        }
    }
}
