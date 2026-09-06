//
//  RunsListView.swift
//  RunTracker
//

import SwiftUI
import MapKit

struct RunsListView: View {
    let runStore: RunStore

    var body: some View {
        Group {
            if runStore.runs.isEmpty {
                ContentUnavailableView(
                    "Henüz koşu yok",
                    systemImage: "figure.run",
                    description: Text("Bir koşuyu bitirdiğinde burada görünecek.")
                )
            } else {
                List(runStore.runs) { run in
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            HStack(spacing: 12) {
                                Label(String(format: "%.2f km", run.distance / 1000), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                Label(formattedDuration(run.duration), systemImage: "stopwatch")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Koşularım")
    }
}

struct RunDetailView: View {
    let run: Run

    var body: some View {
        VStack {
            Map(initialPosition: .automatic) {
                if run.route.count > 1 {
                    MapPolyline(coordinates: run.route)
                        .stroke(.red, lineWidth: 4)
                }
            }

            HStack {
                Spacer()
                VStack {
                    Text("Mesafe").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.2f km", run.distance / 1000)).font(.title3)
                }
                Spacer()
                VStack {
                    Text("Süre").font(.caption).foregroundStyle(.secondary)
                    Text(formattedDuration(run.duration)).font(.title3)
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle(run.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}
