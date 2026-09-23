//
//  HomeView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import SwiftUI
import WeatherKit
import SwiftData
import MapKit

struct HomeView: View {
    @Environment(User.self) private var user

    /// Uygulama genelinde paylaşılan tek üretim motoru (bkz. `RunTrackerApp`).
    /// Ana ekranın kendi motoru vardı: MapKit kotasını Run sekmesinden habersiz
    /// harcıyor, öğrendiği dolambaç katsayısını saklamıyor ve ürettiği rotayı
    /// Run sekmesiyle paylaşmıyordu.
    @Environment(RouteViewModel.self) private var routes
    @State private var locationManager = LocationManager()
    @State private var timeOfDayMessage = "Ready to get moving?"

    @Query private var currentWeekSessions: [RunSession]

    init() {
        _currentWeekSessions = Query(filter: RunSession.currentWeekPredicate(),
                                     sort: \.startedAt, order: .reverse)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.stack) {
                    ScreenHeader(title: user.name, subtitle: timeOfDayMessage)
                        .padding(.bottom, 2)

                    weeklyProgress

                    if let location = locationManager.userLocation {
                        ForecastView(location: location)
                    } else {
                        locationPlaceholder
                    }

                    recentRuns
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 28)
            }
            .screenBackground()
            // Başlık içerikte; gezinme çubuğu boş kalsın ki ekran krem zeminle
            // tek parça görünsün.
        }
        .task(id: locationManager.userLocation == nil) {
            timeOfDayMessage = Self.greeting()
            guard let location = locationManager.userLocation else { return }

            // Rota, havadan ÖNCE ve ondan bağımsız istenir. Eskiden hava
            // çağrısının arkasındaydı: hava servisi yanıt vermediğinde kart
            // sonsuza kadar "Generating" yazıyor, rota hiç istenmiyordu.
            routes.generateIfNeeded(from: location.coordinate, targetKilometers: user.targetDistance)
        }
    }

    // MARK: - Haftalık ilerleme

    /// Haftanın özeti: hedefe ne kadar kalmış. Ana ekranın en üstteki sayısı
    /// budur çünkü kullanıcının "bugün koşmalı mıyım" sorusunu doğrudan
    /// cevaplayan tek şey odur.
    private var weeklyProgress: some View {
        let target = user.weeklyTarget.converted(to: .kilometers).value
        let done = currentWeekSessions.reduce(0) { $0 + $1.distanceInKm }
        let fraction = target > 0 ? done / target : 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "This week")
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(fraction >= 1 ? .secondaryGreen : .secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(done.formatted(.number.precision(.fractionLength(done < 10 ? 1 : 0))))
                    .font(.display(40, weight: .bold))
                Text("of \(target.formatted(.number.precision(.fractionLength(0)))) km")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ProgressBar(value: fraction)

            Text(remainingMessage(done: done, target: target))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func remainingMessage(done: Double, target: Double) -> String {
        guard done < target else { return "Weekly goal reached. Nice work." }
        let left = target - done
        return "\(left.formatted(.number.precision(.fractionLength(1)))) km to go — \(user.motivation.title.lowercased())."
    }

    // MARK: - Son koşular

    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Recent runs")
                if !currentWeekSessions.isEmpty {
                    NavigationLink {
                        SessionListView()
                    } label: {
                        Text("All")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
            }

            if currentWeekSessions.isEmpty {
                EmptyStateView(
                    icon: "figure.run",
                    title: "No runs yet this week",
                    message: "Head to the Run tab to generate a route or start a free run."
                )
                .card()
            } else {
                // Eskiden burada bir `List` vardı, hem de bir `ScrollView`'ın
                // içinde: iki kaydırma alanı iç içe geçtiği için satırlar sabit
                // yükseklikte kırpılıyor ve liste kendi başına kayıyordu.
                LazyVStack(spacing: 10) {
                    ForEach(currentWeekSessions.prefix(3)) { session in
                        NavigationLink {
                            RunSessionDetailView(session: session)
                        } label: {
                            RunSessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var locationPlaceholder: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for your location")
                    .font(.cardTitle)
                Text("The forecast and route suggestions need it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private static func greeting() -> String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<5: return "Good night"
        case 5..<11: return "Good morning"
        case 11..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }
}

#Preview {
    HomeView()
        .environment(
            User(
                name: "Alp",
                sex: .male,
                bday: .now,
                heightCM: 1.8,
                weightKG: 75,
                targetDistance: 5,
                motivation: .hobby
            )
        )
        .environment(RouteViewModel())
        .modelContainer(for: [User.self, RunSession.self, TraveledPath.self], inMemory: true)
}
