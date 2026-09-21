//
//  SessionListView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 16.09.2026.
//

import SwiftUI
import SwiftData
import MapKit

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
//struct RunSessionRow: View {
//    let session: RunSession
//    var body: some View {
//        NavigationLink(destination: RunSessionDetailView(session: session)) {
//            VStack(alignment: .leading, spacing: 6) {
//                HStack {
//                    // Rotalı koşu ile serbest koşu simgeden ayırt edilir.
//                    Image(systemName: session.plannedDistance == nil ? "figure.run" : "map")
//                        .foregroundStyle(.tint)
//                    Text(session.startedAt, format: .dateTime.day().month().year().hour().minute())
//                        .font(.headline)
//                }
//                
//                HStack(spacing: 16) {
//                    Label(session.distanceMeasurement.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2)))),
//                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
//                    Label(formatted(seconds: session.duration), systemImage: "stopwatch")
//                    if let pace = session.pace {
//                        Label("\(formatted(seconds: pace)) /km", systemImage: "speedometer")
//                    }
//                }
//                .font(.subheadline)
//                .foregroundStyle(.secondary)
//            }
//            .padding(.vertical, 4)
//        }
//    }
//    
//    /// Süreyi dk:sn (bir saati aşarsa sa:dk:sn) biçiminde yazar.
//    private func formatted(seconds: TimeInterval) -> String {
//        Duration.seconds(seconds).formatted(
//            .time(pattern: seconds < 3600 ? .minuteSecond : .hourMinuteSecond)
//        )
//    }
//}

struct RunSessionRow: View {
    let session: RunSession
    @State private var district: String = "Run"
    @State private var cameraPosition: MapCameraPosition = .automatic
    @Environment(User.self) private var user

    var body: some View {
        NavigationLink(destination: RunSessionDetailView(session: session)) {
            VStack {
                HStack{
                    VStack(alignment: .leading) {
                        HStack{
                            Image(systemName: session.plannedDistance == nil ? "figure.run" : "map")
                            Text(session.plannedDistance == nil ? "Free Run" : "Route")
                        }
                        .font(.title)
                        
                        Text(district)
                                .font(.caption)
                        Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                    }
                    Spacer()
                    Map(position: $cameraPosition) {
                        ForEach(Array(session.traveledPath!.polylines.enumerated()), id: \.offset) { _, polyline in
                            MapPolyline(polyline)
                                .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .mapControlVisibility(.hidden)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(width: 90, height: 90)
                }
                HStack{
                    statView(title: "Distance", stat: session.distanceMeasurement.formatted())
                    Divider()
                    statView(title: "Time", stat: session.duration.mmss)
                    Divider()
                    let paceDif = (user.avgPace - session.pace!) / user.avgPace
                    HStack{
                        statView(title: "Pace", stat: session.pace!.mmss)
                        Image(systemName: paceDif >= 0 ? "arrow.up" : "arrow.down")
                            .foregroundStyle(paceDif >= 0 ? .green : .red)
                            .bold()
                        Text(paceDif.formatted(.percent.precision(.fractionLength(1))))
                            .font(.caption)
                            .foregroundStyle(paceDif >= 0 ? .green : .red)
                            .bold()
                    }
                }
            }
            .task {
                district = (try? await session.district) ?? "Run"
            }

        }
    }
    
    @ViewBuilder
    func statView(title: String, stat: String) -> some View {
        VStack(alignment: .leading){
            Text(title)
                .font(.caption)
                .bold()
            Text(stat)
                .font(.title2)
        }
    }
}

