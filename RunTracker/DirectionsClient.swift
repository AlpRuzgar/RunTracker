//
//  DirectionsClient.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 15.09.2026.
//

import Foundation
import MapKit
import CoreLocation

// Ağ katmanı: MKDirections'a giden her istek buradan geçer. Geometriden
// habersizdir; yalnızca "A'dan B'ye yürüme bacağı" ister, sonuçları saklar ve
// aynı anda uçan istek sayısını sınırlar.

// MARK: - Tek istek

/// Tek bir yürüme isteği. Protokol yalnızca testlerde MapKit yerine sahte bir
/// ağ koyabilmek için var.
protocol DirectionsProviding {
    /// İki nokta arasındaki yürüme rotası. `nil`: aralarında yürünebilir yol yok
    /// (kalıcı sonuç, tekrar sormaya gerek yok). Geçici durumlarda
    /// `DirectionsFailure` fırlatır.
    func walkingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MKRoute?
}

enum DirectionsFailure: Error {
    /// Sunucu istekleri sınırlıyor (`MKError.loadingThrottled`).
    case throttled
    /// Sunucuya ulaşılamadı ya da geçici bir sunucu hatası oluştu.
    case unavailable
}

struct MapKitDirections: DirectionsProviding {
    func walkingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .walking

        do {
            return try await MKDirections(request: request).calculate().routes.first
        } catch let error as MKError {
            switch error.code {
            case .directionsNotFound, .placemarkNotFound:
                return nil
            case .loadingThrottled:
                throw DirectionsFailure.throttled
            default:
                throw DirectionsFailure.unavailable
            }
        } catch {
            throw DirectionsFailure.unavailable
        }
    }
}

// MARK: - Eşzamanlılık sınırı

/// Aynı anda en fazla `limit` isteğin uçmasına izin veren async semafor.
///
/// MapKit Directions sunucusu kısa sürede gelen istek patlamalarını hızla
/// `loadingThrottled` ile keser. Bir döngünün tüm bacaklarını aynı anda göndermek
/// (sınırsız `TaskGroup`) tam olarak bu patlamayı üretir. 2 eşzamanlı istek,
/// sıralı göndermeye göre bekleme süresini yaklaşık yarıya indirir ama sunucuya
/// patlama olarak görünmez. Sınır bu nesneyi paylaşan herkes için geçerlidir:
/// eski bir üretim iptal edilirken yenisi başlasa bile toplam aşılmaz.
///
/// Projenin varsayılan izolasyonu gereği ana aktörde yaşar: durum yalnızca oradan
/// değiştiği için kilide gerek yok ve `release` senkron (`defer` içinde) çağrılabilir.
final class RequestGate {
    private let limit: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func acquire() async {
        guard inFlight >= limit else {
            inFlight += 1
            return
        }
        // Yer açılınca `release` yerini doğrudan sıradakine devreder; sayaç değişmez.
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            inFlight -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Hız sınırı

/// İsteklerin sunucuya gidiş HIZINI sınırlar. `RequestGate` yalnızca aynı anda
/// uçan istek sayısını sınırlar; kısa sürede art arda atılan toplam isteği
/// sınırlamaz. MapKit Directions sunucusu bir cihazdan dakikada ~50 isteğin
/// üzerini `loadingThrottled` ile kesmeye başlar; bu sınırlayıcı sürekli hızı
/// onun altında tutarak throttle'ın hiç tetiklenmemesini amaçlar.
///
/// Token bucket eşdeğeri: `burst` istek beklemesiz gider, sonrası istek başına
/// `interval` beklenir. Boş geçen süre krediyi `burst`e kadar geri doldurur, o
/// yüzden aralıklı kullanan kullanıcı beklemeyi hiç görmez.
final class RequestPacer {
    private let interval: Duration
    private let burst: Int
    /// Bir sonraki isteğin (patlama kredisi yokken) en erken başlama anı.
    private var nextSlot: ContinuousClock.Instant

    init(interval: Duration, burst: Int) {
        self.interval = interval
        self.burst = max(burst, 1)
        // Geçmişte başlatılır ki ilk `burst` istek beklemesiz gitsin; kredi
        // sınırı zaten her turda `waitTurn` içinde uygulanır.
        self.nextSlot = .now - interval * self.burst
    }

    /// Sıradaki istek için zaman ayırır ve gerekirse o ana kadar bekler.
    /// `interval` sıfırsa hiç beklenmez (testler sahte ağla böyle çalışır).
    func waitTurn() async throws {
        guard interval > .zero else { return }
        let now = ContinuousClock.now
        // Kredi birikimi `burst` ile sınırlı: uzun boşluktan sonra bile en
        // fazla `burst` istek beklemesiz gider.
        nextSlot = max(nextSlot, now - interval * (burst - 1))
        let startAt = nextSlot
        nextSlot = startAt + interval
        if startAt > now {
            try await Task.sleep(until: startAt)
        }
    }
}

// MARK: - Bacak cache'i

/// Yürüme bacaklarını çeker ve saklar.
///
/// Çekmek ile kullanmak ayrı adımlardır: `prefetch` eksik bacakları ağdan cache'e
/// doldurur, `legs(around:)` cache'ten okur. Bunun iki faydası var:
/// 1. İstek atılmadan önce maliyet bilinir (`missingCount`): üretim, bütçesi
///    yetmeyecek bir turu hiç başlatmaz; yarıda kesmek zorunda kalmaz.
/// 2. Throttle ile kesilen bir turda o ana kadar gelen bacaklar kaybolmaz;
///    tur tekrarlandığında yalnızca eksikler istenir.
final class LegFetcher {
    enum Leg {
        case route(MKRoute)
        /// Bu iki nokta arasında yürünebilir yol yok (kalıcı; tekrar istenmez).
        case noRoute
    }

    /// ~1 m çözünürlüklü anahtar. Küçük kaymalar `LoopShape.pin` ile önceden
    /// elendiği için bulanık eşleştirmeye gerek yok: aynı koordinat = aynı anahtar.
    private struct Key: Hashable {
        let from: [Int]
        let to: [Int]

        init(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) {
            self.from = [Int((from.latitude * 1e5).rounded()), Int((from.longitude * 1e5).rounded())]
            self.to = [Int((to.latitude * 1e5).rounded()), Int((to.longitude * 1e5).rounded())]
        }
    }

    private let provider: any DirectionsProviding
    private let gate: RequestGate
    private let pacer: RequestPacer
    private var cache: [Key: Leg] = [:]
    /// Bu sayıyı aşan cache yeni bir üretimin başında boşaltılır — asla üretim
    /// sırasında değil; yoksa bir turun bacakları okunmadan silinebilirdi.
    private let capacity = 400

    /// Ağa giden toplam istek sayısı (throttle yiyenler dahil).
    private(set) var requestCount = 0

    init(provider: any DirectionsProviding, maxConcurrentRequests: Int, requestBurst: Int, requestPacing: Duration) {
        self.provider = provider
        self.gate = RequestGate(limit: maxConcurrentRequests)
        self.pacer = RequestPacer(interval: requestPacing, burst: requestBurst)
    }

    /// Yeni bir üretimin başında çağrılır.
    func trimIfNeeded() {
        if cache.count > capacity { cache.removeAll() }
    }

    /// Kapalı bir yolun (son noktadan başa dönülür) kaç bacağı için ağa gidilmesi gerektiği.
    func missingCount(around ring: [CLLocationCoordinate2D]) -> Int {
        Set(pairs(around: ring).map { Key($0.from, $0.to) }).count { cache[$0] == nil }
    }

    /// Eksik bacakları çeker. Throttle ya da ağ hatasında kardeş istekler iptal
    /// edilir ve hata fırlatılır; o ana kadar gelen bacaklar cache'te kalır.
    func prefetch(around ring: [CLLocationCoordinate2D]) async throws {
        var pending: [Key: (from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)] = [:]
        for pair in pairs(around: ring) where cache[Key(pair.from, pair.to)] == nil {
            pending[Key(pair.from, pair.to)] = pair
        }
        guard !pending.isEmpty else { return }

        // Tüm bacaklar gruba eklenir ama her biri `gate`ten sıra alır: grup
        // yapısal iptali sağlar, gate eşzamanlılığı sınırlar.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for pair in pending.values {
                group.addTask { try await self.load(from: pair.from, to: pair.to) }
            }
            try await group.waitForAll()
        }
    }

    /// Kapalı yolun bacakları, sırayla; cache'te olmayan bacak `nil`.
    func legs(around ring: [CLLocationCoordinate2D]) -> [Leg?] {
        pairs(around: ring).map { cache[Key($0.from, $0.to)] }
    }

    private func load(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws {
        await gate.acquire()
        defer { gate.release() }
        // Sıra beklerken tur iptal edildiyse (kardeş bacak throttle yedi) istek atma.
        try Task.checkCancellation()
        // Sıra beklerken kardeş bir istek bu bacağı doldurmuş olabilir (ör. ters
        // yönün "yol yok" cevabı iki yönü de yazar); boşuna ağa gitme.
        guard cache[Key(from, to)] == nil else { return }
        try await pacer.waitTurn()

        requestCount += 1
        if let route = try await provider.walkingRoute(from: from, to: to) {
            cache[Key(from, to)] = .route(route)
        } else {
            // Yürünebilirlik simetriktir: A→B arasında yol yoksa B→A da yoktur;
            // ters yön hiç sorulmadan işaretlenir. Rotanın kendisi için bu
            // yapılamaz: MKRoute'un çizgisi ve adımları yönlüdür, ters çevrilemez.
            cache[Key(from, to)] = .noRoute
            cache[Key(to, from)] = .noRoute
        }
    }

    private func pairs(around ring: [CLLocationCoordinate2D]) -> [(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)] {
        ring.indices.map { (ring[$0], ring[($0 + 1) % ring.count]) }
    }
}
