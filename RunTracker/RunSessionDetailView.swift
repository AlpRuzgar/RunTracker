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
                .overlay(alignment: .bottom) {
                    detailOverlay()
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .padding()
                }
            }
        }
    }
    
    @ViewBuilder
    func detailOverlay() -> some View {
        VStack {
            HStack {
                Spacer()
                StatView(title: "Distance", stat: session.distanceMeasurement.formatted(.measurement(width: .abbreviated)))
                Divider()
                StatView(title: "Time", stat: session.duration.mmss)
                Divider()
                StatView(title: "Pace", stat: session.pace!.mmss)
                Spacer()
                if let path = session.traveledPath {
                        Button("", systemImage: path.isFavorite ? "star.fill" : "star") { path.isFavorite.toggle() ; print("is path favorite: \(path.isFavorite)")}
                            .foregroundStyle(.yellow)
                }
                Spacer()
            }
            .frame(height: 75)
            
            if let path = session.traveledPath {
                NavigationLink(destination: NavigationView(route: path)) {
                    Label("Run this path again", systemImage: "arrow.trianglehead.counterclockwise")
                }
                .padding()
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .background(.emerald)
            }
        }
        .padding()
    }
}
