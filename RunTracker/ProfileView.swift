//
//  ProfileView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 6.09.2026.
//

import SwiftUI
import SwiftData
import CoreLocation

struct ProfileView: View {
    /// Onboarding'de oluşturulan kullanıcı; `RootView` environment'a koyar.
    @Environment(User.self) private var user
    /// Oturumlar doğrudan değil, kullanıcı ilişkisi üzerinden okunur;
    /// böylece liste onboarding'de oluşturulan kullanıcıya bağlıdır.

    @Query private var currentWeekSessions: [RunSession]

    init() {
        _currentWeekSessions = Query(filter: RunSession.currentWeekPredicate(),
                                     sort: \.startedAt, order: .reverse)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.stack) {
                    ScreenHeader(title: "Profile")
                        .padding(.bottom, 2)
                    profileBar
                    weeklyGoal
                    lifetimeStats
                    sessionsThisWeek
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 28)
            }
            .screenBackground()
        }
    }

    // MARK: - Kimlik

    private var profileBar: some View {
        HStack(spacing: 14) {
            Image(user.avatar.image)
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 62)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.display(22, weight: .semibold))
                Text("Running since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            NavigationLink {
                EditProfileView()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.lightBlue)
                    .frame(width: 40, height: 40)
                    .background(Color.lightBlue.opacity(0.12), in: .circle)
            }
            .accessibilityLabel("Edit profile")
        }
        .card()
    }

    // MARK: - Haftalık hedef

    private var weeklyGoal: some View {
        let target = user.weeklyTarget.converted(to: .kilometers).value
        let done = currentWeekSessions.reduce(0) { $0 + $1.distanceInKm }
        let fraction = target > 0 ? done / target : 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Weekly goal")
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(fraction >= 1 ? .emerald : .secondary)
            }

            ProgressBar(value: fraction)

            HStack {
                Text("\(done.formatted(.number.precision(.fractionLength(1)))) km done")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Spacer()
                Text("\(target.formatted(.number.precision(.fractionLength(0)))) km target")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: - Tüm zamanlar

    private var lifetimeStats: some View {
        let total = Measurement(value: user.sessions.reduce(0) { $0 + $1.distanceMeasurement.value },
                                unit: UnitLength.meters)

        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "All time")
            HStack(alignment: .top, spacing: 8) {
                // `usage` verilmezse biçimlendirici birimi kendi seçer ve
                // 0 km'yi "0 cm" diye yazar; `asProvided` kilometreyi sabitler.
                StatView(
                    title: "Distance",
                    stat: total.converted(to: .kilometers)
                        .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                                numberFormatStyle: .number.precision(.fractionLength(1)))),
                    tint: .brightOrange
                )
                StatView(title: "Time", stat: user.totalDuration.mmss)
                StatView(title: "Avg pace", stat: user.avgPace.mmss)
                StatView(title: "Runs", stat: "\(user.sessionCount)")
            }
        }
        .card()
    }

    // MARK: - Bu haftanın koşuları

    private var sessionsThisWeek: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "This week")
                NavigationLink {
                    SessionListView()
                } label: {
                    Text("All")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }

            if currentWeekSessions.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "Nothing logged this week",
                    message: "Your runs will show up here."
                )
                .card()
            } else {
                // `ScrollView` içinde `List` kullanılmıyor: iki kaydırma alanı
                // iç içe geçtiğinde satırlar kırpılıyordu.
                LazyVStack(spacing: 10) {
                    ForEach(currentWeekSessions) { session in
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
}

extension TimeInterval {
    var mmss: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ProfileView()
        .environment(
            User(
                name: "Alp",
                sex: .male,
                bday: .now,
                heightCM: 175,
                weightKG: 70,
                targetDistance: 5,
                motivation: .hobby
            )
        )
        .modelContainer(for: [User.self, RunSession.self, TraveledPath.self], inMemory: true)
}
