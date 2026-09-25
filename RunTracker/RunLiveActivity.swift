//
//  RunLiveActivity.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 23.09.2026.
//

import Foundation
import ActivityKit

/// Bir koşu ekranının Live Activity'sini yönetir: ekran açılınca başlatır,
/// koşu boyunca günceller, ekran kapanınca bitirir.
///
/// Görünüm her konum güncellemesinde `update` çağırır; hangisinin gerçekten
/// sisteme gideceğine burası karar verir (bkz. `minimumInterval`).
@MainActor
final class RunLiveActivity {
    typealias State = RunActivityAttributes.ContentState

    /// Durum/talimat değişmedikçe iki güncelleme arasındaki en kısa süre.
    /// Konum saniyede bir gelir; her birini göndermek sistemin Live Activity
    /// güncelleme bütçesini tüketir ve etkinlik bir süre donar. Süre zaten
    /// kendiliğinden işlediği için 5 sn'de bir mesafe/tempo yeterince canlı.
    private let minimumInterval: Duration = .seconds(5)

    private var activity: Activity<RunActivityAttributes>?
    private var lastPushed: State?
    private var lastPushAt: ContinuousClock.Instant?

    /// Etkinliği başlatır. Kullanıcı Live Activity'leri kapattıysa sessizce
    /// hiçbir şey yapmaz: koşu ekranı etkinliksiz de eksiksiz çalışır.
    func start(kind: RunActivityAttributes.Kind, state: State) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(
            attributes: RunActivityAttributes(kind: kind),
            content: ActivityContent(state: state, staleDate: nil)
        )
        lastPushed = state
        lastPushAt = .now
    }

    /// Yeni durumu gönderir. Aşama ya da talimat değiştiyse hemen — kullanıcı
    /// dönüşü kaçırmasın; yalnızca sayılar değiştiyse en fazla
    /// `minimumInterval`'da bir.
    func update(_ state: State) {
        guard let activity, state != lastPushed else { return }
        let isSignificant = state.phase != lastPushed?.phase
            || state.instruction != lastPushed?.instruction
            || state.startedAt != lastPushed?.startedAt
        if !isSignificant, let lastPushAt, ContinuousClock.now - lastPushAt < minimumInterval { return }

        lastPushed = state
        lastPushAt = .now
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Etkinliği bitirir. Kaydedilen bir koşu son hâliyle bir dakika kilit
    /// ekranında kalır (özet gibi); vazgeçilen koşu hemen kaybolur.
    func end(finalState: State? = nil) {
        guard let activity else { return }
        self.activity = nil
        lastPushed = nil
        lastPushAt = nil
        let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = finalState == nil ? .immediate : .after(.now.addingTimeInterval(60))
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    /// Önceki bir oturumdan kalan etkinlikleri kapatır. Uygulama koşu sırasında
    /// sonlandırılırsa etkinlik kilit ekranında donmuş hâlde kalıyordu; artık
    /// ona bağlı bir koşu ekranı olmadığı için açılışta temizlenir.
    static func endStaleActivities() async {
        for activity in Activity<RunActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ortalama tempo (sn/km). İlk metrelerde GPS gürültüsü tempoyu saçma
    /// değerlere (km'de 40 dk gibi) fırlattığı için 50 m'den önce hesaplanmaz.
    static func pace(distance: Double, since startedAt: Date?) -> Double? {
        guard let startedAt, distance >= 50 else { return nil }
        return Date.now.timeIntervalSince(startedAt) / (distance / 1000)
    }
}
