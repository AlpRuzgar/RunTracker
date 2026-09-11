//
//  ProfileView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query var sessions: [RunSession]
    var body: some View {
        NavigationStack {
            VStack {
                
            }
            .navigationTitle("Profile")
        }
    }
}

/// Tek bir koşu kaydının özeti: tarih, mesafe, süre ve tempo.
private struct RunSessionRow: View {
    let session: RunSession

    var body: some View {
        NavigationLink(destination: RunSessionDetailView(session: session)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    // Rotalı koşu ile serbest koşu simgeden ayırt edilir.
                    Image(systemName: session.plannedDistance == nil ? "figure.run" : "map")
                        .foregroundStyle(.tint)
                    Text(session.startedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.headline)
                }
                
                HStack(spacing: 16) {
                    Label(String(format: "%.2f km", session.distanceInKm), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Label(formatted(seconds: session.duration), systemImage: "stopwatch")
                    if let pace = session.pace {
                        Label("\(formatted(seconds: pace)) /km", systemImage: "speedometer")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    /// Süreyi dk:sn (bir saati aşarsa sa:dk:sn) biçiminde yazar.
    private func formatted(seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .time(pattern: seconds < 3600 ? .minuteSecond : .hourMinuteSecond)
        )
    }
}

#Preview {
    ProfileView()
}
