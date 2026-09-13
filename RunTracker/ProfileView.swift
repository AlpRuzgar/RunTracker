//
//  ProfileView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import SwiftUI
import SwiftData
import CoreLocation

enum SortOption: Identifiable, CaseIterable {
    case date
    case distance
    case duration
    case pace
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .date:
            return "By Date"
        case .distance:
            return "By Distance"
        case .duration:
            return "By Duration"
        case .pace:
            return "By Pace"
        }
    }
}

struct ProfileView: View {
    @Query private var sessions: [RunSession]
    /// `@Query` sonucu salt-okunur olduğundan, seçili seçeneğe göre
    /// sıralanmış bir kopya döndürülür.
    private var sortedSessions: [RunSession] {
        switch selectedSortOption {
        case .date:
            return sessions.sorted { $0.startedAt > $1.startedAt }
        case .distance:
            return sessions.sorted { $0.distanceInKm > $1.distanceInKm }
        case .duration:
            return sessions.sorted { $0.duration > $1.duration }
        case .pace:
            // Temposu olmayan (ör. mesafesi sıfır) koşular sona alınır.
            return sessions.sorted {
                ($0.pace ?? .greatestFiniteMagnitude) < ($1.pace ?? .greatestFiniteMagnitude)
            }
        }
    }
    
    @State private var selectedSortOption: SortOption = .date
    
    var body: some View {
        NavigationStack {
            VStack {
                List(sortedSessions) { session in
                    RunSessionRow(session: session)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("sort", selection: $selectedSortOption) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.title)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
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
    let container = try! ModelContainer(
        for: RunSession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    /// İstenen uzunlukta (yaklaşık), kuzeye doğru düz bir çizgiden oluşan
    /// tek segment üretir. `RunSession.distance` segmentlerden hesaplandığı
    /// için örnek mesafeler böyle verilir.
    func straightSegment(meters: Double) -> [CLLocationCoordinate2D] {
        let start = CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784)
        // 1 derece enlem ~ 111.320 m
        let end = CLLocationCoordinate2D(latitude: start.latitude + meters / 111_320, longitude: start.longitude)
        return [start, end]
    }

    // (mesafe m, süre sn, planlanan mesafe) — tempo/mesafe/süre sıralamaları
    // ayırt edilebilsin diye kasıtlı olarak karışık değerler.
    let samples: [(Double, TimeInterval, Double?)] = [
        (5_200, 1_820, nil),      // 5.2 km, ~5:50 /km
        (3_100, 950, 3_000),      // kısa ve hızlı, rotalı
        (10_050, 3_620, 10_000),  // 10 km, rotalı
        (7_400, 2_590, nil),
        (4_800, 1_450, nil),      // hızlı tempo
        (8_900, 3_300, 9_000),
        (2_300, 900, nil),        // en kısa mesafe
        (6_500, 2_210, nil),
        (12_100, 4_900, 12_000),  // en uzun, rotalı
        (0, 600, nil),            // mesafesiz koşu: pace == nil
    ]

    for (index, sample) in samples.enumerated() {
        let end = Calendar.current.date(byAdding: .day, value: -index, to: .now)!
        let session = RunSession(
            startedAt: end.addingTimeInterval(-sample.1),
            endedAt: end,
            segments: sample.0 > 0 ? [straightSegment(meters: sample.0)] : [],
            plannedDistance: sample.2
        )
        container.mainContext.insert(session)
    }

    return ProfileView()
        .modelContainer(container)
}
