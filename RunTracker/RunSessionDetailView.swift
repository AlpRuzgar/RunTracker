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
            }
        }
    }
}
