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

    /// İlk rotada varsayılan tahmin %23 uzun çıkar, tek düzeltmede tutar. İkinci
    /// rotada öğrenilen dolambaç katsayısıyla ilk tahmin tutar: tek tur, bacak
    /// sayısı kadar istek.
    @Test func convergesAndReusesLearnedDetour() async throws {
        let generator = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 1)

        let first = try await generator.generate(from: start, targetDistance: 5_000)
        #expect(first.kind == .loop)
        #expect(abs(first.distanceError) <= generator.policy.tolerance)
        #expect(generator.lastStats.evaluations == 2)

        let second = try await generator.generate(from: start, targetDistance: 5_000)
        #expect(abs(second.distanceError) <= generator.policy.tolerance)
        #expect(generator.lastStats.evaluations == 1)
        #expect(generator.lastStats.requests == second.legs.count)
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
        final class MemoryStore: DetourStoring {
            var factors: [String: Double] = [:]
            func loadDetourFactors() -> [String: Double] { factors }
            func saveDetourFactors(_ factors: [String: Double]) { self.factors = factors }
        }
        let store = MemoryStore()

        let first = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 1, detourStore: store)
        _ = try await first.generate(from: start, targetDistance: 5_000)
        #expect(!store.factors.isEmpty)

        let second = RouteGenerator(provider: FakeDirections(), policy: fastPolicy(), seed: 1, detourStore: store)
        _ = try await second.generate(from: start, targetDistance: 5_000)
        #expect(second.lastStats.evaluations == 1)
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
