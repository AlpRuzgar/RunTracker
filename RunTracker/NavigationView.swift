//
//  NavigationView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit
import SwiftData

/// Üretilmiş bir döngü rotasında adım adım navigasyon ekranı: sıradaki manevrayı
/// üstte, kalan mesafeyi ve ilerlemeyi altta gösterir. Rota takibi ve yeniden
/// rota `NavigationViewModel`'dedir; bu görünüm yalnızca konumları iletir.
///
/// Koşu boyunca kullanıcının geçtiği yol kaydedilir; "End route" bu yolu bir
/// `RunSession` olarak saklar.
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

    var body: some View {
        Map(position: $camera.position) {
            UserAnnotation()
            // Yeniden rota sonrası çizgiler değiştiği için rota değil,
            // view model'in güncel çizgileri çizilir.
            // Döngü rotasında çizgi tek başına hangi yöne koşulacağını
            // göstermez; yönü oklar taşır. Oklar view model'de hesaplanmıştır:
            // ekran her konum güncellemesinde yeniden çizilir.
            RouteOverlay(
                polylines: navigation.polylines,
                mapHeading: mapHeading,
                arrows: navigation.arrows
            )
            // Gerçekte koşulan yol, planlanan rotanın üstünde ayrı renkte.
            RunRouteOverlay(segments: locationManager.pathSegments)
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
            instructionBanner
        }
        .safeAreaInset(edge: .bottom) {
            statsBar
        }
        .onAppear {
            // Takip burada başlamaz: kullanıcı rotaya yaklaşınca view model
            // kendiliğinden `navigating`e geçer, koşu o an başlar.
            // `LocationManager` konumları takip kapalıyken de yayınladığı için
            // yaklaşma yine de izlenebilir.
            navigation.start(path: followedPath)
        }
        .onDisappear {
            navigation.stop()
            locationManager.stopTracking()
        }
        .onChange(of: locationManager.userLocation) { _, newLocation in
            guard let newLocation else { return }
            navigation.update(location: newLocation)
            if !hasStarted, navigation.state == .navigating { beginRun() }
            camera.follow(location: newLocation, heading: locationManager.travelDirection)
        }
        .onChange(of: locationManager.userHeading) { _, _ in
            // Kullanıcı dururken dönerse harita yine de onunla dönsün.
            camera.follow(location: locationManager.userLocation, heading: locationManager.travelDirection)
        }
    }

    /// Ekranın tek gezinme öğesi: navigasyon tam ekran açıldığı için gezinme
    /// çubuğu yoktur, geri dönüş bu düğmeyle olur. Koşuyu KAYDETMEZ — kaydeden
    /// düğme alttaki "End route".
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
        }
        .glassEffect(.regular, in: .circle)
        .accessibilityLabel("Back")
    }

    /// Gerçekte takip edilen yol: ters yön seçildiyse rotanın ters çevrilmiş hâli.
    private var followedPath: any FollowablePath {
        isReversed ? route.reversed() : route
    }

    /// Sıradaki manevrayı ya da navigasyonun genel durumunu gösteren üst şerit;
    /// geri düğmesini de o taşır.
    private var instructionBanner: some View {
        HStack(spacing: 12) {
            backButton
            bannerContent
                .frame(maxWidth: .infinity)
            // Görünmez eş: metin geri düğmesinin yanında değil, şeridin
            // ortasında dursun.
            backButton.hidden()
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
    }

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
                    Text("\(formatted(meters: distanceToRoute)) away — starts automatically")
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
                    .foregroundStyle(.brightOrange)
            case .finished:
                Label("Run complete", systemImage: "flag.checkered")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.emerald)
            default:
                Text(navigation.currentInstruction)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(formatted(meters: navigation.distanceToNextManeuver))
                    .font(.display(15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Kalan mesafe, ilerleme çubuğu ve koşuyu bitirme düğmesini taşıyan alt şerit.
    private var statsBar: some View {
        VStack(spacing: 14) {
            ProgressBar(value: navigation.progressFraction, height: 6)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatted(meters: navigation.remainingDistance))
                        .font(.display(24, weight: .bold))
                        .monospacedDigit()
                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 34).overlay(Color.primary.opacity(0.12))

                VStack(alignment: .leading, spacing: 2) {
                    // Süre koşu başlayana kadar işlemez: rotaya yürürken geçen
                    // dakikalar koşunun temposunu bozardı.
                    if hasStarted {
                        Text(startedAt, style: .timer)
                            .font(.display(24, weight: .bold))
                            .monospacedDigit()
                    } else {
                        Text("--:--")
                            .font(.display(24, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(hasStarted ? "elapsed" : "not started")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                // Takip kapatılınca kullanıcı haritayı serbestçe inceleyebilir.
                Button {
                    camera.isFollowing.toggle()
                } label: {
                    Image(systemName: camera.isFollowing ? "location.fill" : "location.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(camera.isFollowing ? .brightOrange : .secondary)
                        .frame(width: 38, height: 38)
                }
                .glassEffect(.regular, in: .circle)
                .accessibilityLabel(camera.isFollowing ? "Stop following" : "Follow me")
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
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 6)
    }

    /// Kullanıcı rotaya yaklaştı: koşu bu an başlar. Süre ve yol kaydı buradan
    /// itibaren işler.
    private func beginRun() {
        hasStarted = true
        startedAt = .now
        locationManager.startTracking()
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

        let session = RunSession(
            startedAt: startedAt,
            segments: locationManager.pathSegments,
            // Planlanan mesafe rotanın tamamı değil kullanıcının katıldığı
            // yerden bitişe olan kısmıdır; ortadan başlayan koşu, hedefini
            // tutturamamış gibi görünmemeli.
            plannedDistance: navigation.journeyDistance
        )
        let path = TraveledPath(
            name: "Route run — \(startedAt.formatted(date: .abbreviated, time: .shortened))",
            segments: session.segments
        )
        session.traveledPath = path
        session.user = users.first
        modelContext.insert(session)
        navigation.stop()
        dismiss()
    }

    /// Mesafeyi sistemin varsayılan birimiyle yazar.
    private func formatted(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2))))
    }
}
