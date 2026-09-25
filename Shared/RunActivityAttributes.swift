//
//  RunActivityAttributes.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 23.09.2026.
//

// Bu dosya HEM uygulamaya HEM RunTrackerWidgets eklentisine derlenir: Live
// Activity'yi uygulama başlatıp günceller, eklenti çizer; ikisinin aynı tipi
// görmesi gerekir. Bu yüzden içinde uygulamaya özgü hiçbir tipe dokunulmaz.

import ActivityKit
import AppIntents
import Foundation

/// Kilit ekranı ve Dynamic Island'daki koşu etkinliği.
///
/// Sabit kısım yalnızca koşunun türüdür; geri kalan her şey `ContentState`'tedir
/// ve koşu boyunca güncellenir.
nonisolated struct RunActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable {
        /// Üretilmiş ya da kayıtlı bir rotada navigasyon: talimat ve ilerleme var.
        case navigation
        /// Rotasız koşu: yalnızca koşu bilgileri.
        case freeRun
    }

    enum Phase: String, Codable, Hashable {
        /// Navigasyon kuruldu, kullanıcı rotaya yaklaşmayı bekliyor; süre işlemez.
        case waitingToStart
        case running
        case rerouting
        /// Rota tamamlandı ama koşu henüz kaydedilmedi.
        case finished
        /// Koşu kaydedildi; etkinlik kapanmadan önce son hâlini gösterir.
        case ended
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        /// Süre bu andan itibaren sayılır; koşu başlamadıysa `nil`.
        ///
        /// Süre güncelleme olarak gönderilmez: `Text(timerInterval:)` kendi
        /// kendine işler. Saniyede bir güncelleme hem bütçeyi yer hem pili.
        var startedAt: Date?
        /// Bitirilen koşunun süresi (yalnızca `ended`); sayaç o anda donar.
        var finalDuration: TimeInterval?
        /// Koşulan mesafe (metre).
        var distance: Double
        /// Ortalama tempo (saniye / km); anlamlı mesafe koşulmadıysa `nil`.
        var secondsPerKilometer: Double?

        // Yalnızca navigasyon:
        /// Sıradaki manevra talimatı.
        var instruction: String?
        /// Sıradaki manevraya kalan mesafe (metre).
        var distanceToManeuver: Double?
        /// Yolculuğun tamamlanan kısmı, 0...1.
        var progress: Double?
        /// Koşu başlamadan önce rotaya olan uzaklık (metre).
        var distanceToRoute: Double?
    }

    var kind: Kind
}

/// Live Activity'deki "End" düğmesi: koşuyu kaydedip bitirir.
///
/// `LiveActivityIntent` olduğu için `perform()` eklentide değil UYGULAMANIN
/// sürecinde çalışır; koşu ekranı açıkken kayıt oradaki model bağlamıyla
/// yapılır. Eklenti bu tipi yalnızca düğmeyi kurmak için görür.
struct EndRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End run"
    static let description = IntentDescription("Saves and ends the current run.")

    func perform() async throws -> some IntentResult {
        await RunActivityBridge.endRun?()
        return .result()
    }
}

/// Eklentinin göremediği uygulama koduna açılan kapı: açık koşu ekranı
/// kendi bitirme eylemini buraya bağlar, `EndRunIntent` onu çağırır. Eklentide
/// hep `nil` kalır.
enum RunActivityBridge {
    static var endRun: (() -> Void)?
}
