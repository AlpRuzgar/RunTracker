//
//  SessionListView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 16.09.2026.
//

import SwiftUI
import SwiftData

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

struct SessionListView: View {
    @Environment(User.self) private var user
    @Environment(\.modelContext) private var modelContext
    private var sessions: [RunSession] { user.sessions }
    /// `@Query` sonucu salt-okunur olduğundan, seçili seçeneğe göre
    /// sıralanmış bir kopya döndürülür.
    ///
    
    @Query private var currentWeekSessions: [RunSession]

    init() {
        _currentWeekSessions = Query(filter: RunSession.currentWeekPredicate(), sort: \.startedAt)
    }


    @State private var selectedSortOption: SortOption = .date

    private var sortedSessions: [RunSession] {
        switch selectedSortOption {
        case .date:
            return sessions.sorted { $0.startedAt > $1.startedAt }
        case .distance:
            return sessions.sorted { $0.distanceInKm > $1.distanceInKm }
        case .duration:
            return sessions.sorted { $0.duration > $1.duration }
        case .pace:
            return sessions.sorted {
                ($0.pace ?? .greatestFiniteMagnitude) < ($1.pace ?? .greatestFiniteMagnitude)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                List(sessions){ session in
                    RunSessionRow(session: session)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(session)
                            }
                        }
                }
            }
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
            .navigationTitle("Runs")
        }
    }

    private func delete(_ session: RunSession) {
        modelContext.delete(session)
    }
}

/// Tek bir koşu kaydının özeti: tarih, mesafe, süre ve tempo.
struct RunSessionRow: View {
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
                    Label(session.distanceMeasurement.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2)))),
                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
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
        for: RunSession.self, TraveledPath.self, User.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let user = User(
        name: "Alp",
        sex: .male,
        bday: Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))!,
        heightCM: 180,
        weightKG: 72,
        targetDistance: 5,
        motivation: .condition
    )
    container.mainContext.insert(user)

    func date(_ day: Int, _ month: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    // (başlangıç, mesafe m, süre sn, planlanan mesafe m)
    let samples: [(Date, Double, TimeInterval, Double?)] = [
        // 14–18 Eylül 2026
        (date(18, 9, 7, 15), 5_030, 25 * 60 + 30, 5_000),
        (date(17, 9, 18, 40), 8_210, 47 * 60 + 10, nil),
        (date(17, 9, 6, 50), 3_120, 14 * 60 + 5, nil),
        (date(16, 9, 19, 5), 10_550, 61 * 60 + 30, 10_000),
        (date(16, 9, 7, 0), 4_400, 26 * 60 + 24, nil),
        (date(15, 9, 12, 30), 6_780, 33 * 60 + 54, 7_000),
        (date(15, 9, 6, 45), 2_500, 15 * 60, nil),
        (date(14, 9, 17, 20), 12_300, 74 * 60, 12_000),
        (date(14, 9, 8, 10), 5_800, 30 * 60 + 10, nil),
        (date(14, 9, 21, 0), 1_610, 8 * 60, nil),
        // 14 Eylül öncesi
        (date(12, 9, 7, 30), 7_240, 40 * 60, nil),
        (date(11, 9, 18, 0), 4_020, 21 * 60 + 30, 4_000),
        (date(9, 9, 6, 40), 9_660, 58 * 60, nil),
        (date(7, 9, 8, 0), 21_100, 118 * 60, 21_100),
        (date(5, 9, 19, 15), 3_500, 17 * 60 + 30, nil),
        (date(3, 9, 7, 10), 6_000, 36 * 60, nil),
        (date(1, 9, 17, 45), 5_500, 29 * 60, 5_000),
        (date(29, 8, 8, 30), 8_850, 50 * 60, nil),
        (date(26, 8, 6, 55), 4_750, 24 * 60 + 30, nil),
        (date(23, 8, 18, 20), 11_200, 68 * 60, 11_000),
    ]

    for (start, distance, duration, planned) in samples {
        let session = RunSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            segments: [],
            plannedDistance: planned
        )
        // init mesafeyi segmentlerden hesapladığı için burada elle atanır.
        session.distance = distance
        session.user = user
        container.mainContext.insert(session)
    }

    return SessionListView()
        .modelContainer(container)
        .environment(user)
}

