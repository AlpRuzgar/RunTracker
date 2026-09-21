//
//  RouteGeneratorTests.swift
//  RunTrackerTests
//
//  Created by Alp Rüzgar on 15.09.2026.
//

import Testing
import MapKit
import CoreLocation
@testable import RunTracker

// Üretim motorunun uçtan uca davranışı; MapKit yerine sahte bir yürüme ağı
// kullanılır. Ağ deterministik olduğu için sabit tohumla her koşu aynı sonucu verir.

private let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)

/// Yalnızca mesafe ve çizgisi değiştirilmiş `MKRoute`.
private final class StubRoute: MKRoute {
    private let stubDistance: CLLocationDistance
    private let stubPolyline: MKPolyline

    init(coordinates: [CLLocationCoordinate2D], distance: CLLocationDistance) {
        stubDistance = distance
        stubPolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        super.init()
    }

    override var distance: CLLocationDistance { stubDistance }
    override var polyline: MKPolyline { stubPolyline }
}

/// Sahte yürüme ağı: bacaklar düz çizgi, mesafe `detourFactor` kadar uzun.
@MainActor
private final class FakeDirections: DirectionsProviding {
    /// Yol mesafesi / kuş uçuşu. Varsayılan tahmin (1.3) bilerek tutturulmaz.
    var detourFactor = 1.6
    /// Bu sıradaki istekler (1'den başlar) throttle yer.
    var throttledRequests: Set<Int> = []
    var throttlesEverything = false
    /// `false` dönen nokta çiftleri arasında yol yoktur.
    var isWalkable: (CLLocationCoordinate2D, CLLocationCoordinate2D) -> Bool = { _, _ in true }

    private(set) var requestCount = 0
    private(set) var maxInFlight = 0
    /// Başarıyla cevaplanan bacaklar; aynı bacağın iki kez istenip istenmediğini görmek için.
    private(set) var servedLegs: [String] = []
    private var inFlight = 0

    func walkingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MKRoute? {
        requestCount += 1
        let number = requestCount
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }

        // Gecikme, isteklerin gerçekten üst üste binmesini sağlar.
        try await Task.sleep(for: .milliseconds(2))

        if throttlesEverything || throttledRequests.contains(number) { throw DirectionsFailure.throttled }
        guard isWalkable(from, to) else { return nil }

        servedLegs.append("\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)")
        return StubRoute(coordinates: [from, to], distance: Geo.distance(from, to) * detourFactor)
    }
}

/// Bellekte yaşayan sahte kalıcı bellek.
private final class MemoryStore: GenerationStoring {
    var factors: [String: Double] = [:]
    var history: [[Double]] = []

    func loadDetourFactors() -> [String: Double] { factors }
    func saveDetourFactors(_ factors: [String: Double]) { self.factors = factors }
    func loadRouteHistory() -> [[Double]] { history }
    func saveRouteHistory(_ history: [[Double]]) { self.history = history }
}

/// Bacak başına dolambacı değişen sahte ağ. `FakeDirections` her bacağa aynı
/// katsayıyı uyguladığı için yakınsama gerçekte olduğundan kolaydır; burada her
/// bacak kendi katsayısını alır, yani toplam mesafe ilk tahminin etrafında
/// gerçekçi biçimde saçılır.
@MainActor
private final class NoisyDirections: DirectionsProviding {
    private(set) var requestCount = 0

    func walkingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MKRoute? {
        requestCount += 1
        // Koordinattan türeyen tekrarlanabilir gürültü: aynı bacak aynı cevabı verir.
        var hash = UInt64(bitPattern: Int64((from.latitude + to.longitude) * 1e7))
        hash = hash &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let factor = 1.15 + 0.6 * Double(hash >> 40) / Double(UInt64(1) << 24)
        return StubRoute(coordinates: [from, to], distance: Geo.distance(from, to) * factor)
    }
}

@MainActor
struct RouteGeneratorTests {
    /// Sahte ağla gerçek zamanlı beklemelerin (hız sınırı, backoff) anlamı yok;
    /// hepsi kapatılır ya da milisaniyeye indirilir.
    private func fastPolicy() -> GenerationPolicy {
        var policy = GenerationPolicy()
        policy.backoffBase = .milliseconds(1)
        policy.throttleBackoff = .milliseconds(1)
        policy.requestPacing = .zero
        return policy
    }

    /// Varsayılan tahmin (1.3) sahte ağın 1.6'lık dolambacına göre %23 kısa
    /// kalır; bu kabul eşiğinin (±%20) dışında olduğu için bir düzeltme turu
    /// yapılır. İkinci rotada öğrenilen katsayıyla ilk tahmin tutar: tek tur,
    /// bacak sayısı kadar istek.
    @Test func convergesAndReusesLearnedDetour() async throws {
        let generator = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 1)

        let first = try await generator.generate(from: start, targetDistance: 5_000)
        #expect(first.kind == .loop)
        #expect(abs(first.distanceError) <= generator.policy.acceptance)
        #expect(generator.lastStats.evaluations == 2)

        let second = try await generator.generate(from: start, targetDistance: 5_000)
        #expect(abs(second.distanceError) <= generator.policy.acceptance)
        #expect(generator.lastStats.evaluations == 1)
        #expect(generator.lastStats.requests == second.legs.count)
    }

    /// Kabul eşiğinin (±%20) içinde kalan ilk ölçüm yakınsamayı bitirir: daha sıkı
    /// olan `tolerance`a (±%10) inmek için fazladan düzeltme turu ATILMAZ. Eskiden
    /// solver yalnızca `tolerance`a bakıyor, elde kabul edilebilir rota varken
    /// bacak sayısı kadar isteği iki kez daha harcıyordu.
    @Test func stopsAtAcceptanceWithoutExtraCorrectionRounds() async throws {
        let network = FakeDirections()
        // İlk tahmin %15 uzun düşer: kabul aralığında, tolerans aralığının dışında.
        network.detourFactor = DetourEstimate.initial * 1.15
        let generator = RouteGenerator(provider: network, policy: fastPolicy(), seed: 11)

        let route = try await generator.generate(from: start, targetDistance: 5_000)

        #expect(generator.lastStats.evaluations == 1)
        #expect(generator.lastStats.requests == route.legs.count)
        #expect(abs(route.distanceError) > generator.policy.tolerance)
        #expect(abs(route.distanceError) <= generator.policy.acceptance)
    }

    /// HEDEF: sıradan bir üretim patlama kredisinin (`requestBurst`) içinde
    /// kalmalı. Kaldığı sürece süreyi ağ gecikmesi belirler; taştığı anda her
    /// istek `requestPacing` kadar bekler ve üretim saniyelerce uzar.
    ///
    /// Aynı ölçüm eski yakınsama kuralıyla (yalnızca `tolerance`a inene kadar
    /// devam et) üretim başına 21 isteğe kadar çıkıyordu.
    @Test func typicalGenerationFitsInTheRequestBurst() async throws {
        let generator = RouteGenerator(provider: NoisyDirections(), policy: fastPolicy(), seed: 21)

        for _ in 0..<5 {
            let route = try await generator.generate(from: start, targetDistance: 5_000)
            #expect(generator.lastStats.requests <= generator.policy.requestBurst)
            #expect(generator.lastStats.evaluations <= 2)
            #expect(abs(route.distanceError) <= generator.policy.fallbackTolerance)
        }
    }

    /// Hız sınırının dakikalık toplamı MapKit'in gözlemlenen throttle eşiğinin
    /// (~50/dk) altında kalmalı: patlama + bir dakikada dolan kredi.
    @Test func sustainedRequestRateStaysUnderThrottleThreshold() {
        let policy = GenerationPolicy()
        let perMinute = Double(policy.requestBurst) + 60 / Double(policy.requestPacing.components.seconds)
        #expect(perMinute <= 50)
    }

    /// Eşzamanlılık sınırı hem uygulanıyor (aşılmıyor) hem kullanılıyor (sıralı değil).
    @Test func keepsRequestConcurrencyAtPolicyLimit() async throws {
        let network = FakeDirections()
        let generator = RouteGenerator(provider: network, policy: fastPolicy(), seed: 2)

        _ = try await generator.generate(from: start, targetDistance: 8_000)

        #expect(network.maxInFlight == generator.policy.maxConcurrentRequests)
        #expect(generator.lastStats.requests <= generator.policy.requestBudget)
    }

    /// Tek bir throttle üretimi öldürmez: beklenir, tur kaldığı yerden sürer ve
    /// gelmiş bacaklar yeniden istenmez.
    @Test func recoversFromThrottleWithoutRefetchingLegs() async throws {
        let network = FakeDirections()
        network.detourFactor = DetourEstimate.initial
        network.throttledRequests = [2]
        let generator = RouteGenerator(provider: network, policy: fastPolicy(), seed: 3)

        let route = try await generator.generate(from: start, targetDistance: 5_000)

        #expect(route.kind == .loop)
        #expect(generator.lastStats.recoveries == 1)
        #expect(Set(network.servedLegs).count == network.servedLegs.count)
    }

    /// Throttle'dan toparlanma hakkı TEK: ikinci throttle'da kısa beklemelerle
    /// ısrar edilmez, anlamlı bir hata döner (UI bunun üstüne geri sayım koyar).
    @Test func persistentThrottleEndsWithRateLimitError() async throws {
        let network = FakeDirections()
        network.throttlesEverything = true
        let generator = RouteGenerator(provider: network, policy: fastPolicy(), seed: 4)

        await #expect(throws: RouteGenerationError.rateLimited) {
            try await generator.generate(from: start, targetDistance: 5_000)
        }
        #expect(generator.lastStats.recoveries == generator.policy.maxThrottleRecoveries)
    }

    /// İlk kullanımda (geçmiş yok) döngü imkânsızsa hata değil git-gel rota gelir.
    /// Burada waypoint'ler arasında hiç yol yok; yalnızca başlangıca gidip gelinebilir.
    @Test func fallsBackToOutAndBackWhenNoLoopExists() async throws {
        let network = FakeDirections()
        network.isWalkable = { from, to in Geo.distance(from, start) < 1 || Geo.distance(to, start) < 1 }
        let generator = RouteGenerator(provider: network, policy: fastPolicy(), seed: 5)

        let route = try await generator.generate(from: start, targetDistance: 5_000)

        #expect(route.kind == .outAndBack)
        #expect(abs(route.distanceError) <= generator.policy.fallbackTolerance)
        #expect(generator.lastStats.requests <= generator.policy.requestBudget)
    }

    /// Aynı yerden art arda üretilen rotalar farklı yönlere açılır ve eşikten
    /// fazla örtüşmez.
    @Test func consecutiveRoutesTakeDifferentStreets() async throws {
        let generator = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 6)
        let policy = generator.policy

        var routes: [GeneratedRoute] = []
        for _ in 0..<3 {
            routes.append(try await generator.generate(from: start, targetDistance: 5_000))
        }

        for (previous, next) in zip(routes, routes.dropFirst()) {
            let overlap = RouteFootprint(Geo.joinedCoordinates(of: next.polylines)).overlap(
                with: RouteFootprint(Geo.joinedCoordinates(of: previous.polylines)),
                corridor: policy.overlapCorridor,
                excluding: start,
                startZone: policy.startZone
            )
            #expect(overlap <= policy.maxOverlap)
            #expect(Geo.angularDifference(previous.bearing, next.bearing) > 60)
        }
    }

    /// Rastgelelik kontrollü: aynı tohum aynı rotayı, farklı tohum farklı rotayı verir.
    @Test func seedControlsRandomness() async throws {
        func route(seed: UInt64) async throws -> GeneratedRoute {
            try await RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: seed)
                .generate(from: start, targetDistance: 6_000)
        }

        let a = try await route(seed: 99)
        let b = try await route(seed: 99)
        let c = try await route(seed: 100)

        #expect(a.distance == b.distance)
        #expect(a.bearing == b.bearing)
        #expect(a.legs.count == b.legs.count)
        #expect(a.bearing != c.bearing)
    }

    /// Hız sınırı: patlama hakkı beklemesiz gider, sonrası istek başına en az
    /// `interval` bekler. `Task.sleep` en az bekleneni garanti ettiği için alt
    /// sınır deterministiktir.
    @Test func pacerLimitsSustainedRequestRate() async throws {
        let pacer = RequestPacer(interval: .milliseconds(20), burst: 2)
        let clock = ContinuousClock()

        let elapsed = try await clock.measure {
            for _ in 0..<5 { try await pacer.waitTurn() }
        }

        // 2 beklemesiz + 3 aralıklı → en az 60 ms.
        #expect(elapsed >= .milliseconds(60))
    }

    /// Öğrenilen dolambaç katsayısı store üzerinden oturumlar arasında taşınır:
    /// yeni bir generator (yeni oturum) bilinen bölgede ilk tahmini öğrenilmiş
    /// katsayıyla yapar ve tek turda kabul edilir.
    @Test func persistsLearnedDetourAcrossGenerators() async throws {
        let store = MemoryStore()

        let first = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 1, store: store)
        _ = try await first.generate(from: start, targetDistance: 5_000)
        #expect(!store.factors.isEmpty)

        let second = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 1, store: store)
        _ = try await second.generate(from: start, targetDistance: 5_000)
        #expect(second.lastStats.evaluations == 1)
    }

    /// Rota geçmişi de oturumlar arasında taşınır: yeni bir generator (yeni
    /// oturum) bir öncekinin rotasını hatırlar ve aynı yerden farklı bir yöne
    /// açılır. Eskiden geçmiş yalnızca bellekte yaşadığı için her açılışta ilk
    /// rota bir önceki oturumunkinin kopyası olabiliyordu.
    @Test func persistsRouteHistoryAcrossGenerators() async throws {
        let store = MemoryStore()

        let first = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 1, store: store)
        let previous = try await first.generate(from: start, targetDistance: 5_000)
        #expect(!store.history.isEmpty)

        // Aynı tohum: geçmiş olmasa ikisi birebir aynı rotayı üretirdi.
        let second = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 1, store: store)
        let next = try await second.generate(from: start, targetDistance: 5_000)

        #expect(Geo.angularDifference(previous.bearing, next.bearing) > 60)
    }

    /// Çevredeki her yön kullanılmışken: iskeleti eski rotaların üstüne düşen
    /// şekiller AĞA HİÇ GİDİLMEDEN elenir, ama eleme yalnızca boşluktan yer —
    /// `maxLoopAttempts` gerçek deneme yine de yapılır ve sonuç yine bir döngü
    /// olur. Elemenin deneme hakkını yiyebilmesi, kullanıcıya döngü yerine
    /// git-gel rotası verirdi.
    @Test func skipsNearDuplicateShapesWithoutGivingUpOnLoops() async throws {
        let store = MemoryStore()
        store.history = [blanketHistoryEntry(around: start, radius: 1_200)]
        let generator = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 7, store: store)
        let policy = generator.policy

        let route = try await generator.generate(from: start, targetDistance: 2_000)

        // Boşluğun tamamı elemeye gider…
        #expect(generator.lastStats.skippedShapes == policy.maxShapeCandidates - policy.maxLoopAttempts)
        // …ama denemeler korunur ve rota yine döngü olur.
        #expect(generator.lastStats.attempts == policy.maxLoopAttempts)
        #expect(route.kind == .loop)
    }

    /// Geçmiş boşken hiçbir şekil elenmez: eleme yalnızca gerçekten benzer
    /// şekilleri kesmeli, sıradan üretimi yavaşlatmamalı.
    @Test func doesNotSkipShapesWithoutHistory() async throws {
        let generator = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 8)

        _ = try await generator.generate(from: start, targetDistance: 5_000)

        #expect(generator.lastStats.skippedShapes == 0)
        #expect(generator.lastStats.attempts == 1)
    }

    /// Başlangıcın çevresini tümüyle kaplayan sahte bir rota izi: `radius`
    /// yarıçaplı kareyi 40 m aralıklı satırlarla tarar, yani her nokta bir
    /// önceki rotadan en fazla 20 m uzakta kalır. `RouteFootprint` girdiyi bir
    /// yol gibi yeniden örneklediği için satır uçları yeter.
    private func blanketHistoryEntry(around center: CLLocationCoordinate2D, radius: Double) -> [Double] {
        var values = [center.latitude, center.longitude, 0.0]
        var north = -radius
        var isRightwards = true
        while north <= radius {
            let easts = isRightwards ? [-radius, radius] : [radius, -radius]
            for east in easts {
                let point = Geo.move(from: center, east: east, north: north)
                values.append(point.latitude)
                values.append(point.longitude)
            }
            north += 40
            isRightwards.toggle()
        }
        return values
    }

    /// Yürünemeyen bacak iki yönde de cache'lenir: A→B'ye "yol yok" cevabı
    /// geldiyse B→A ağa hiç sorulmaz.
    @Test func cachesNoRouteBidirectionally() async throws {
        let network = FakeDirections()
        network.isWalkable = { _, _ in false }
        // Tek eşzamanlı istek: ters yönün cache'ten karşılanması deterministik olsun.
        let fetcher = LegFetcher(provider: network, maxConcurrentRequests: 1, requestBurst: 6, requestPacing: .zero)
        let a = start
        let b = CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)

        try await fetcher.prefetch(around: [a, b])

        // Halka a→b ve b→a'dan oluşur; tek istek ikisini de karşılamalı.
        #expect(network.requestCount == 1)
        #expect(fetcher.missingCount(around: [a, b]) == 0)
    }
}

