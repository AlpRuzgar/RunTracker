//
//  NavigationView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import UIKit
import MapKit
import SwiftData

/// Üretilmiş bir döngü rotasında adım adım navigasyon ekranı: sıradaki manevrayı
/// üstte, kalan mesafeyi ve ilerlemeyi altta gösterir. Rota takibi ve yeniden
/// rota `NavigationViewModel`'dedir; bu görünüm yalnızca konumları iletir.
///
/// Koşu boyunca kullanıcının geçtiği yol kaydedilir; "End route" (ya da bitişe
/// varınca "Save run") bu yolu bir `RunSession` olarak saklar.
struct NavigationView: View {
    /// Takip edilecek yol — üretilmiş bir rota ya da kaydedilmiş bir koşu yolu.
    let route: any FollowablePath
    /// Yol ters yönde mi takip edilecek? Seçim ekran açılmadan önce yapılır;
    /// burada yalnızca uygulanır (bkz. `ReversedPath`).
    var isReversed = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]

    @State private var locationManager = LocationManager()
    @State private var navigation = NavigationViewModel()
    @State private var camera = RunCamera()
    /// Haritanın kuzeye göre dönüklüğü; oklar buna göre hizalanır.
    @State private var mapHeading = 0.0
    @State private var startedAt = Date.now
    /// Koşu gerçekten başladı mı? Kullanıcı rotaya yaklaşana kadar ne süre işler
    /// ne de yol kaydedilir; yoksa rotaya gitmek için yürünen mesafe koşuya
    /// yazılırdı.
    @State private var hasStarted = false
    /// Rotanın bitişine varıldığı an. Koşu burada biter: süre donar, yol kaydı
    /// durur ve alt panel özet + "Save run"a döner. Kullanıcı kaydetmeden önce
    /// yürümeye devam etse bile koşuya yazılmaz.
    @State private var finishedAt: Date?
    /// Kilit ekranı ve Dynamic Island'daki talimat + koşu kartı.
    @State private var liveActivity = RunLiveActivity()

    var body: some View {
        Map(position: $camera.position) {
            UserAnnotation()
            // Geride kalan kısım sönük çizilir, önde kalan kısım yeşil ve
            // oklu: haritada tek bir çizgi göze çarpar, o da gidilecek yol.
            // Gerçekte koşulan yol ayrıca çizilmez — rotanın üstüne binen
            // ikinci bir çizgi haritayı kalabalıklaştırıyordu. Oklar view
            // model'de bir kez hesaplanır; ekran her kamera karesinde yeniden
            // çizilir.
            if let completed = navigation.completedPolyline {
                MapPolyline(completed)
                    .stroke(Color.gray.opacity(0.55), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            RouteOverlay(
                polylines: navigation.upcomingPolyline.map { [$0] } ?? [],
                mapHeading: mapHeading,
                arrows: navigation.upcomingArrows
            )
        }
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
        }
        .mapControls {
            MapUserLocationButton()
            MapPitchToggle()        // Toggles between flat 2D and tilted 3D modes
            MapScaleView()          // Shows distance/scale legend during zoom
        }
        .safeAreaInset(edge: .top) {
            RunTopBanner { bannerContent }
        }
        .safeAreaInset(edge: .bottom) {
            statsBar
        }
        // Arka plan konumu rotaya yürürken de açıktır: kullanıcı telefonu
        // cebine koyup rotaya yürüyebilir, koşu yine kendiliğinden başlar.
        .runScreenLifecycle(
            locationManager: locationManager,
            camera: camera,
            liveActivity: liveActivity,
            kind: .navigation,
            activityState: { activityState() },
            endRun: { endRun() },
            onStart: {
                // Takip burada başlamaz: kullanıcı rotaya yaklaşınca view model
                // kendiliğinden `navigating`e geçer, koşu o an başlar.
                // `LocationManager` konumları takip kapalıyken de yayınladığı
                // için yaklaşma yine de izlenebilir.
                navigation.start(path: followedPath)
                // Navigasyonda ekran bakılmak için açıktır; kendiliğinden
                // kararıp kilitlenmesin. Yalnızca bu ekran açıkken.
                UIApplication.shared.isIdleTimerDisabled = true
            },
            onLocation: { location in
                navigation.update(location: location)
                if !hasStarted, navigation.state == .navigating { beginRun() }
            },
            onStop: {
                navigation.stop()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        )
        .onChange(of: navigation.state) { _, state in
            if state == .finished { finishRun() }
            // Yeniden rota konumdan bağımsız, ağ isteği bitince değişir.
            liveActivity.update(activityState())
        }
    }

    /// Gerçekte takip edilen yol: ters yön seçildiyse rotanın ters çevrilmiş hâli.
    private var followedPath: any FollowablePath {
        isReversed ? route.reversed() : route
    }

    /// Sıradaki manevrayı ya da navigasyonun genel durumunu gösteren üst şerit içeriği.
    @ViewBuilder
    private var bannerContent: some View {
        VStack(spacing: 4) {
            switch navigation.state {
            case .waitingToStart:
                Label("Move closer to the route", systemImage: "figure.walk")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                // Rotaya olan uzaklık, kullanıcının doğru yöne gidip gitmediğini
                // anlaması için canlı gösterilir.
                if let distanceToRoute = navigation.distanceToRoute {
                    Text("\(Self.formatted(guidance: distanceToRoute)) away — starts automatically")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Waiting for your location…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .rerouting:
                Label("Rerouting…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primaryBlue)
            case .finished:
                Label("Run complete", systemImage: "flag.checkered")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondaryGreen)
            case .navigating where navigation.isOffRoute:
                // Yeniden rota birkaç güncelleme sonra gelir; o zamana kadar
                // koşucu rotadan çıktığını buradan anlar ve geri dönebilir.
                Label("Off route", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primaryBlue)
                if let distanceToRoute = navigation.distanceToRoute {
                    Text("\(Self.formatted(guidance: distanceToRoute)) from the route")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            default:
                Text(navigation.currentInstruction)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(Self.formatted(guidance: navigation.distanceToNextManeuver))
                    .font(.display(15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Alt panel: koşu sürerken canlı sayılar, bitişe varınca koşunun özeti.
    private var statsBar: some View {
        RunBottomPanel {
            if let finishedAt {
                finishSummary(endedAt: finishedAt)
            } else {
                liveStats
            }
        }
    }

    /// Kalan mesafe, süre, tempo, ilerleme çubuğu ve koşuyu bitirme düğmesi.
    @ViewBuilder
    private var liveStats: some View {
        ProgressBar(value: navigation.progressFraction, height: 6)

        HStack(alignment: .center, spacing: 12) {
            RunStat(label: "remaining") {
                Text(formatted(meters: navigation.remainingDistance))
            }

            RunStatDivider()

            // Süre koşu başlayana kadar işlemez: rotaya yürürken geçen
            // dakikalar koşunun temposunu bozardı.
            RunStat(label: hasStarted ? "elapsed" : "not started") {
                if hasStarted {
                    Text(startedAt, style: .timer)
                } else {
                    Text("--:--").foregroundStyle(.secondary)
                }
            }

            RunStatDivider()

            RunStat(label: "avg pace") {
                Text(paceText(until: .now))
            }

            Spacer(minLength: 0)

            FollowToggle(camera: camera, tint: .secondaryGreen)
        }

        // Koşu başlamadan önce bitirilecek bir şey yok: düğme o hâlde
        // ikincil kalır, kaydedilen koşuyu sonlandıran eylemle aynı
        // ağırlıkta görünmesin.
        if hasStarted {
            Button { endRun() } label: {
                Label("End route", systemImage: "stop.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            Button { endRun() } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    /// Bitişe varılmış koşunun özeti ve kaydetme düğmesi. Sayılar varış anında
    /// donmuştur.
    @ViewBuilder
    private func finishSummary(endedAt: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RunStat(label: "distance") {
                Text(formatted(meters: distanceRun))
            }

            RunStatDivider()

            RunStat(label: "time") {
                Text(Self.formatted(duration: endedAt.timeIntervalSince(startedAt)))
            }

            RunStatDivider()

            RunStat(label: "avg pace") {
                Text(paceText(until: endedAt))
            }

            Spacer(minLength: 0)
        }

        Button { endRun() } label: {
            Label("Save run", systemImage: "checkmark")
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    /// Kullanıcı rotaya yaklaştı: koşu bu an başlar. Süre ve yol kaydı buradan
    /// itibaren işler.
    private func beginRun() {
        hasStarted = true
        startedAt = .now
        locationManager.startTracking()
    }

    /// Bitişe varıldı: süre donar ve yol kaydı durur. Koşu henüz KAYDEDİLMEZ;
    /// kullanıcı özeti görüp "Save run"a basar (ya da kilit ekranından "End").
    private func finishRun() {
        guard hasStarted, finishedAt == nil else { return }
        finishedAt = .now
        locationManager.stopTracking()
    }

    /// Koşuyu bitirir: geçilen yolu bir `RunSession` ve yeni bir `TraveledPath`
    /// olarak kaydedip ekranı kapatır.
    private func endRun() {
        locationManager.stopTracking()

        // Koşu hiç başlamadıysa (kullanıcı rotaya yaklaşmadan vazgeçti)
        // kaydedilecek bir şey yok.
        guard hasStarted else {
            navigation.stop()
            dismiss()
            return
        }

        liveActivity.end(finalState: activityState(phase: .ended))
        RunSession.saveFinishedRun(
            startedAt: startedAt,
            endedAt: finishedAt ?? .now,
            segments: locationManager.pathSegments,
            // Planlanan mesafe rotanın tamamı değil kullanıcının katıldığı
            // yerden bitişe olan kısmıdır; ortadan başlayan koşu, hedefini
            // tutturamamış gibi görünmemeli.
            plannedDistance: navigation.journeyDistance,
            pathName: "Route run",
            user: users.first,
            in: modelContext
        )
        navigation.stop()
        dismiss()
    }

    /// Şu ana kadar koşulan mesafe (metre).
    private var distanceRun: Double {
        RunSession.distance(of: locationManager.pathSegments)
    }

    /// Live Activity'de gösterilen talimat ve koşu bilgileri. Aşama verilmezse
    /// navigasyonun durumundan çıkarılır.
    private func activityState(phase: RunActivityAttributes.Phase? = nil) -> RunLiveActivity.State {
        let distance = distanceRun
        let phase = phase ?? {
            switch navigation.state {
            case .idle, .waitingToStart: .waitingToStart
            case .navigating: .running
            case .rerouting: .rerouting
            case .finished: .finished
            }
        }()
        // Bitişe varıldıysa kilit ekranındaki sayaç da o anda donar.
        let endedAt = finishedAt ?? .now
        return RunLiveActivity.State(
            phase: phase,
            startedAt: hasStarted ? startedAt : nil,
            finalDuration: phase == .ended || finishedAt != nil ? endedAt.timeIntervalSince(startedAt) : nil,
            distance: distance,
            secondsPerKilometer: hasStarted ? RunLiveActivity.pace(distance: distance, since: startedAt, until: endedAt) : nil,
            instruction: navigation.currentInstruction,
            distanceToManeuver: navigation.distanceToNextManeuver,
            progress: navigation.progressFraction,
            distanceToRoute: navigation.distanceToRoute
        )
    }

    /// Ortalama tempo, dakika:saniye / km. Anlamlı mesafe koşulmadıysa ya da
    /// tempo bir saati aşıyorsa (yürüyüş, uzun duraklama) boş.
    private func paceText(until end: Date) -> String {
        guard hasStarted,
              let pace = RunLiveActivity.pace(distance: distanceRun, since: startedAt, until: end),
              pace < 3600 else { return "--:--" }
        return pace.mmss
    }

    /// Koşu istatistiği olarak mesafe: iki ondalık (ör. "3.42 km").
    private func formatted(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2))))
    }

    /// Yol tarifindeki mesafe: iki anlamlı basamak ("150 m", "1.4 km"). Ondalıklı
    /// metre okunmuyor, her GPS güncellemesinde son basamak titriyordu; iki
    /// basamak dönüşe yaklaştıkça hâlâ yeterince hassas.
    static func formatted(guidance meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.significantDigits(1...2))))
    }

    /// Süre: bir saatin altında "12:34", üstünde "1:02:03".
    private static func formatted(duration seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .time(pattern: seconds < 3600 ? .minuteSecond : .hourMinuteSecond)
        )
    }
}
