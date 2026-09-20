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
                    NavigationLink(destination: SessionListView()) {
                        HStack {
                            Text("All Sessions")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .shadow(radius: 5)
                }
                .padding()
                .navigationTitle("Profile")
            }
            .background(LinearGradient(colors: [.emerald, .emerald.opacity(0.1)], startPoint: .bottomTrailing, endPoint: .topLeading))
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
        .background(.white)
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
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 5)
    }
    
    @ViewBuilder
    func lifetimeStats() -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]){
            let totalDistance = Measurement(value: user.sessions.reduce(0) { $0 + $1.distanceMeasurement.value }, unit: UnitLength.meters)
            StatView(icon: "ruler", value: "\(totalDistance.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2)))))")
            
            let totalTime = user.sessions.reduce(0) { $0 + $1.duration }
            StatView(icon: "timer", value: totalTime.mmss)
        }
    }
    
    @ViewBuilder
    func sessionsThisWeek() -> some View {
        VStack {
            if !currentWeekSessions.isEmpty {
                List(currentWeekSessions) { session in
                    RunSessionRow(session: session)
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
    var body: some View {
        VStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.title2)
                .bold()
            card()
        }
        .padding()
        .background(.white)
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
                .tint(.emerald)
        }
        .padding()
    }
}


struct StatView: View {
    let icon: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Image(systemName: icon)
            Text(value)
                .font(.system(size: 30))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .padding()
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
    let container = try! ModelContainer(
        for: User.self, RunSession.self, TraveledPath.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let user = User(
        name: "Alp",
        sex: .male,
        bday: .now,
        heightCM: 180,
        weightKG: 75,
        targetDistance: 5,
        motivation: .hobby
    )
    let session = RunSession(
        startedAt: .now.addingTimeInterval(-30 * 60),
        segments: [[
            CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784),
            CLLocationCoordinate2D(latitude: 41.0122, longitude: 28.9700),
            CLLocationCoordinate2D(latitude: 41.0160, longitude: 28.9784)
        ]]
    )
    container.mainContext.insert(user)
    container.mainContext.insert(session)
    session.user = user
    
    return ProfileView()
        .environment(user)
        .modelContainer(container)
}
