//
//  RunScreenChrome.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 25.09.2026.
//

import SwiftUI
import CoreLocation
import MapKit

// Koşu ekranlarının (`NavigationView`, `FreeRunView`) ortak parçaları. İki
// ekran da tam ekran açılır ve gezinme çubuğu taşımaz: üstte geri düğmesini
// taşıyan bir cam şerit, altta sayıları ve koşuyu bitiren eylemi taşıyan bir cam
// panel vardır. Ekranlar yalnızca bu kalıbın İÇİNİ doldurur; kalıbın kendisi,
// yaşam döngüsü (arka plan konumu, Live Activity, kamera takibi) buradadır.

// MARK: - Üst şerit

/// Ekranın tek gezinme öğesi. Koşuyu KAYDETMEZ — kaydeden eylem alttaki paneldedir.
struct RunBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
        }
        .glassVisual(.regular, in: .circle)
        .accessibilityLabel("Back")
    }
}

/// Geri düğmesi ve ortalanmış içerikten oluşan üst şerit.
struct RunTopBanner<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            RunBackButton()
            content
                .frame(maxWidth: .infinity)
            // Görünmez eş: içerik geri düğmesinin yanında değil, şeridin
            // ortasında dursun.
            RunBackButton().hidden()
        }
        .padding(14)
        .glassVisual(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
    }
}

// MARK: - Alt panel

/// Sayıları ve koşuyu bitiren eylemi taşıyan alt panel.
struct RunBottomPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 14) {
            content
        }
        .padding(16)
        .glassVisual(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 6)
    }
}

/// Paneldeki tek bir canlı sayı ve altındaki etiket.
struct RunStat<Value: View>: View {
    let label: String
    var labelColor: Color = .secondary
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            value
                .font(.display(24, weight: .bold))
                .monospacedDigit()
                // Navigasyonda panelde üç sayı yan yana durur; dar ekranda
                // satır kırılmasın, sayı biraz küçülsün.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(labelColor)
        }
    }
}

/// Panelde iki sayıyı ayıran ince çizgi.
struct RunStatDivider: View {
    var body: some View {
        Divider().frame(height: 34).overlay(Color.primary.opacity(0.12))
    }
}

/// Kameranın kullanıcıyı takibini açıp kapatır. Harita elle oynatılınca takip
/// kendiliğinden kapanır (bkz. `RunCamera.userMovedMap`); bu düğme onu geri açar.
struct FollowToggle: View {
    let camera: RunCamera
    var tint: Color

    var body: some View {
        Button {
            camera.toggleFollowing()
        } label: {
            Image(systemName: camera.isFollowing ? "location.fill" : "location.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(camera.isFollowing ? tint : .secondary)
                .frame(width: 38, height: 38)
        }
        .glassVisual(.regular, in: .circle)
        .accessibilityLabel(camera.isFollowing ? "Stop following" : "Follow me")
    }
}

// MARK: - Yaşam döngüsü

/// İki koşu ekranının ortak yaşam döngüsü.
///
/// - Arka plan konumu ekran açıkken açıktır: telefon kilitlense de kayıt ve
///   Live Activity sürer. Diğer ekranlar bunu açmamalıdır.
/// - Live Activity ekranla başlar, her konumda güncellenir (kendisi seyreltir),
///   ekranla biter. Kilit ekranındaki "End" düğmesi ekranın kendi `endRun`unu
///   çağırır (bkz. `EndRunIntent`).
/// - Kamera her konumda ve pusula yönünde kullanıcıyı takip eder; kullanıcı
///   dururken dönerse harita yine de onunla döner. Kullanıcı haritayı elle
///   oynatınca takip kapanır.
///
/// Ekrana özgü işler kancalarla sıraya sokulur: `onStart` her şeyden önce
/// (Live Activity'nin ilk durumu ona bağlı olabilir), `onLocation` kamera ve
/// Live Activity güncellenmeden önce, `onStop` her şeyden önce çalışır.
private struct RunScreenLifecycle: ViewModifier {
    let locationManager: LocationManager
    let camera: RunCamera
    let liveActivity: RunLiveActivity
    let kind: RunActivityAttributes.Kind
    let activityState: () -> RunLiveActivity.State
    let endRun: () -> Void
    let onStart: () -> Void
    let onLocation: (CLLocation) -> Void
    let onStop: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                onStart()
                locationManager.setRunsInBackground(true)
                liveActivity.start(kind: kind, state: activityState())
                RunActivityBridge.endRun = endRun
            }
            .onDisappear {
                onStop()
                locationManager.stopTracking()
                locationManager.setRunsInBackground(false)
                // Kaydetmeden çıkıldıysa etkinlik hemen kapanır; kaydedildiyse
                // `endRun` onu zaten son hâliyle kapattı.
                liveActivity.end()
                RunActivityBridge.endRun = nil
            }
            .onChange(of: locationManager.userLocation) { _, newLocation in
                if let newLocation { onLocation(newLocation) }
                camera.follow(location: newLocation, heading: locationManager.travelDirection)
                liveActivity.update(activityState())
            }
            .onChange(of: locationManager.userHeading) { _, _ in
                camera.follow(location: locationManager.userLocation, heading: locationManager.travelDirection)
            }
            // Kameranın kendi hareketleri `positionedByUser` değildir; yalnızca
            // kaydırma, yakınlaştırma ve döndürme hareketleri öyledir.
            .onChange(of: camera.position.positionedByUser) { _, byUser in
                if byUser { camera.userMovedMap() }
            }
    }
}

extension View {
    /// Koşu ekranının ortak yaşam döngüsünü bağlar (bkz. `RunScreenLifecycle`).
    func runScreenLifecycle(
        locationManager: LocationManager,
        camera: RunCamera,
        liveActivity: RunLiveActivity,
        kind: RunActivityAttributes.Kind,
        activityState: @escaping () -> RunLiveActivity.State,
        endRun: @escaping () -> Void,
        onStart: @escaping () -> Void = {},
        onLocation: @escaping (CLLocation) -> Void = { _ in },
        onStop: @escaping () -> Void = {}
    ) -> some View {
        modifier(RunScreenLifecycle(
            locationManager: locationManager,
            camera: camera,
            liveActivity: liveActivity,
            kind: kind,
            activityState: activityState,
            endRun: endRun,
            onStart: onStart,
            onLocation: onLocation,
            onStop: onStop
        ))
    }
}
