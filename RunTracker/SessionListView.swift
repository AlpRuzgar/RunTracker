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
        case .date: return "By Date"
        case .distance: return "By Distance"
        case .duration: return "By Duration"
        case .pace: return "By Pace"
        }
    }
}

struct SessionListView: View {
    @Environment(User.self) private var user
    @Environment(\.modelContext) private var modelContext
    private var sessions: [RunSession] { user.sessions }

    @State private var selectedSortOption: SortOption = .date
    @State private var selected: RunSession?

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
            return sessions.sorted {
                ($0.pace ?? .greatestFiniteMagnitude) < ($1.pace ?? .greatestFiniteMagnitude)
            }
        }
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                EmptyStateView(
                    icon: "shoe",
                    title: "No runs yet",
                    message: "Every run you finish is saved here."
                )
                .card()
                .padding(.horizontal, Metrics.gutter)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color.canvas)
            } else {
                // Liste, kart görünümü için sadeleştirilir: satır zemini ve
                // ayraçlar kapatılır, kart biçimini satırın kendisi taşır.
                // `List` yine de kalır — kaydırarak silme onunla gelir.
                List {
                    ForEach(sortedSessions) { session in
                        // `NavigationLink` yerine düğme: liste satırının açılım
                        // oku (>) kartın DIŞINA, kenar boşluğuna düşüyordu.
                        // Gidilecek yer `navigationDestination` ile seçilir.
                        Button {
                            selected = session
                        } label: {
                            RunSessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 5, leading: Metrics.gutter,
                                                  bottom: 5, trailing: Metrics.gutter))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(session)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .screenBackground()
            }
        }
        .navigationDestination(item: $selected) { session in
            RunSessionDetailView(session: session)
        }
        .navigationTitle("Runs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $selectedSortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func delete(_ session: RunSession) {
        modelContext.delete(session)
    }
}

/// Tek bir koşu kaydının özeti: türü, yeri, tarihi ve üç ölçüsü.
struct RunSessionRow: View {
    let session: RunSession
    @State private var district: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    private var polylines: [MKPolyline] { session.segments.polylines }
    @Environment(User.self) private var user

    private var isRoute: Bool { session.plannedDistance != nil }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: isRoute ? "map.fill" : "figure.run")
                            .font(.system(size: 11, weight: .bold))
                        Text(isRoute ? "Route" : "Free run")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(isRoute ? Color.secondaryGreen : Color.brightOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (isRoute ? Color.secondaryGreen : Color.brightOrange).opacity(0.12),
                        in: .capsule
                    )

                    // Semt adı ağdan gelir; gelene kadar satırın yüksekliği
                    // zıplamasın diye yeri tarih satırıyla birlikte korunur.
                    Text(district ?? " ")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .redacted(reason: district == nil ? .placeholder : [])

                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Map(position: $cameraPosition, interactionModes: []) {
                    RouteOverlay(
                        polylines: polylines,
                        tint: isRoute ? .secondaryGreen : .brightOrange,
                        density: .compact
                    )
                }
                .mapControlVisibility(.hidden)
                .allowsHitTesting(false)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
            }

            Divider().overlay(Color.hairline)

            HStack(alignment: .top, spacing: 8) {
                StatView(
                    title: "Distance",
                    stat: session.distanceMeasurement.formatted(
                        .measurement(width: .abbreviated, usage: .road,
                                     numberFormatStyle: .number.precision(.fractionLength(2)))
                    )
                )
                StatView(title: "Time", stat: session.duration.mmss)
                paceStat
            }
        }
        .card()
        .task {
            cameraPosition = .rect(polylines.framingRect())
            district = (try? await session.district) ?? "Run"
        }
    }

    /// Tempo ve kullanıcının ortalamasına göre farkı. Tempo yoksa (mesafesiz
    /// kayıt) kıyas da yapılmaz — eskiden burada zorla açılan `nil` vardı.
    @ViewBuilder
    private var paceStat: some View {
        if let pace = session.pace, user.avgPace > 0 {
            let delta = (user.avgPace - pace) / user.avgPace
            let isFaster = delta >= 0
            VStack(alignment: .leading, spacing: 3) {
                Text("Pace")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(pace.mmss)
                        .font(.statValue.monospacedDigit())
                    Image(systemName: isFaster ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isFaster ? Color.secondaryGreen : Color.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            StatView(title: "Pace", stat: "—")
        }
    }
}

#Preview {
    NavigationStack {
        SessionListView()
    }
    .environment(
        User(name: "Alp", sex: .male, bday: .now, heightCM: 175,
             weightKG: 70, targetDistance: 5, motivation: .hobby)
    )
    .modelContainer(for: [User.self, RunSession.self, TraveledPath.self], inMemory: true)
}
