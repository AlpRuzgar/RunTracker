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
    @Environment(\.colorScheme) private var colorScheme

    init() {
        _currentWeekSessions = Query(filter: RunSession.currentWeekPredicate(),
                                     sort: \.startedAt)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    profileBar()
                    currentStats()
                    InfoCard(title: "Life-time Stats", card: lifetimeStats)
                    InfoCard(title:"This Week's Sessions", card: sessionsThisWeek)
                }
                .padding()
                .navigationTitle("Profile")
            }
            .background(LinearGradient(colors: [.lightBlue, .lightBlue.opacity(0.1)], startPoint: .bottomTrailing, endPoint: .topLeading))
        }
    }
    
    @ViewBuilder
    func profileBar() -> some View {
        HStack{
            Image(user.avatar.image)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            VStack(alignment: .leading) {
                Text(user.name)
                    .font(.system(size: 20))
                Text("Joined at: \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .bold()
            }
            .frame(maxWidth: .infinity)
            
            NavigationLink(destination: EditProfileView()) {
                Image(systemName: "person.badge.gearshape")
                    .font(.system(size: 25))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .background(colorScheme == .dark ? .steelGray : .white)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 5)
    }

    @ViewBuilder
    func currentStats() -> some View {
        VStack {
            let totalDistance = Measurement(value: currentWeekSessions.reduce(0) { $0 + $1.distanceMeasurement.value}, unit: UnitLength.meters)
            let totalDistanceString = totalDistance.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2))))
            let completionPercentage = totalDistance.converted(to: .kilometers).value / user.weeklyTarget.converted(to: .kilometers).value
            HStack {
                Image(systemName: "flag")
                    .bold()
                Text("Weekly goal")
                    .bold()
                Spacer()
                Text(completionPercentage >= 100.0 ? "%100" : completionPercentage.formatted(.percent.precision(.fractionLength(1))))
                    .bold()
            }
            HStack {
                PercentageBarView(progress: completionPercentage)
            }
            HStack {
                Text("\(totalDistanceString)")
                Spacer()
                Text("Target Distance: \(user.weeklyTarget.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...2)))))")
            }
        }
        .padding()
        .background(colorScheme == .dark ? .steelGray : .white)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 5)
    }

    @ViewBuilder
    func lifetimeStats() -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]){
            let totalDistance = Measurement(value: user.sessions.reduce(0) { $0 + $1.distanceMeasurement.value }, unit: UnitLength.meters)
            StatView(title: "Total Distance", stat: "\(totalDistance.converted(to: .kilometers).formatted())")
            StatView(title: "Total Time", stat: user.totalDuration.mmss)
            StatView(title: "Average Pace", stat: user.avgPace.mmss)
        }
    }
    
    @ViewBuilder
    func sessionsThisWeek() -> some View {
        VStack {
            if !currentWeekSessions.isEmpty {
                List(currentWeekSessions) { session in
                    RunSessionRow(session: session)
                }
                NavigationLink(destination: SessionListView()) {
                    HStack {
                        Text("All Sessions")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
            }
            else {
                Text("No sessions this week!")
            }
        }
    }
}

struct RibbonView: View {
    var body: some View {
        
    }
}

struct InfoCard<Card: View>: View {
    var title: String
    @ViewBuilder var card: () -> Card
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.title2)
                .bold()
                .padding(.bottom)
            card()
        }
        .padding()
        .background(colorScheme == .dark ? .steelGray : .white)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 5)
    }
}

struct PercentageBarView: View {
    @State var progress: Double
    
    var body: some View {
        VStack(spacing: 10) {
            // Progress bar showing percentage
            ProgressView(value: progress, total: 1.0)
                .tint(.lightBlue)
        }
        .padding()
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
