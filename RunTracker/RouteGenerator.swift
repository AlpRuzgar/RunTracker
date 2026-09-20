//
//  RouteGenerator.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 15.09.2026.
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Ayarlar

/// Üretimin tüm ayarları ve bunlardan TÜRETİLEN istek bütçesi. Saf bir değer
/// tipi; bütçe formülü ağ olmadan test edilebilir.
nonisolated struct GenerationPolicy {

    // MARK: Şekil

    /// Döngüdeki köşe sayısı (başlangıç dahil) = bir turdaki bacak/istek sayısı.
    /// Üst sınır 5: her köşe tur başına bir istek; 6 köşenin şekle kattığı
    /// çeşitlilik, MapKit kotasından yenen fazladan isteğe değmiyor.
    var vertexCountRange = 4...5
    /// Her denemenin açılış yönüne eklenen rastgele sapma (± derece).
    var bearingJitter = 20.0

    // MARK: Yakınsama

    /// Sapma bunun altına inince yarıçap düzeltmesi durur (±%10).
    var tolerance = 0.10
    /// Döngünün doğrudan kabul edildiği en büyük sapma (±%20). Genişçe tutulur:
    /// ilk tahmin ne kadar sık kabul edilirse düzeltme turunun istekleri o kadar
    /// sık atlanır; hem kota hem bekleme süresi kazanılır.
    var acceptance = 0.20
    /// Yedeklerin (gevşek döngü, git-gel) kabul sınırı (±%25).
    var fallbackTolerance = 0.25
    /// Bir şekil için en fazla yarıçap turu: 1 ilk tahmin + 2 düzeltme. Orantısal
    /// düzeltme tipik olarak 1 düzeltmede ±%10'a indiği için 2'si pay bırakır.
    var maxEvaluations = 3
    /// Kaç farklı döngü şekli denenecek.
    var maxLoopAttempts = 4
    /// Döngü bulunamazsa kaç yönde git-gel denenecek.
    var fallbackAttempts = 3

    // MARK: Cache ve waypoint

    /// Düzeltme turunda bu kadar (metre) kayan waypoint yerinde bırakılır; bkz.
    /// `LoopShape.pin`. Yarım sokak boyundan (~50 m) kısa: MapKit iki noktayı da
    /// çoğunlukla aynı yola oturtur. Navigasyonun rota dışı eşiğinden (40 m) de
    /// kısa: haritada fark görünmez.
    var pinTolerance = 35.0
    /// Waypoint'in oturtulduğu yol bundan uzaksa (metre) waypoint kullanılamaz
    /// sayılır: su, özel arazi, yolsuz alan.
    var maxSnapDistance = 150.0
    /// Kullanılamayan waypoint pivota doğru bu orana çekilir (şekil başına tek onarım).
    var repairPull = 0.6

    // MARK: Çeşitlilik

    /// Yeni rota, aynı yerden üretilmiş son rotalardan biriyle bu orandan fazla
    /// örtüşürse "aynı rota" sayılır.
    ///
    /// Neden 0.6: Başlangıç bölgesi hariç tutulunca farklı yönlere açılan meşru
    /// döngüler tipik olarak %30'un altında örtüşür; aynı sokaklardan geçen
    /// neredeyse-kopyalar %75'in üstünde. 0.6 bu iki kümenin arasında kalır ve tek
    /// çıkışlı yerlerde (köprü, sahil yolu, park içi tek patika) zorunlu ortak
    /// kısımlara pay bırakır. ≤0.4 bu yerlerde meşru rotaları eler; ≥0.8 neredeyse
    /// aynı rotayı "yeni" diye geçirir. Eşik ne olursa olsun üretimi başarısız
    /// yapamaz: yalnızca örtüşme yüzünden elenen aday yedek olarak saklanır.
    var maxOverlap = 0.6
    /// Örtüşmede "aynı sokak" genişliği (metre): karşı kaldırım + çizgi sapması.
    var overlapCorridor = 25.0
    /// Başlangıç çevresinde örtüşme ve tekrar hesabına katılmayan bölge (metre).
    var startZone = 200.0
    /// Kaç son rotayla karşılaştırılır. Tüm geçmişle karşılaştırmak, bir süre sonra
    /// çevredeki her sokak "kullanılmış" sayılacağı için her yeni rotayı eler.
    var diversityWindow = 3
    /// Aynı sokağı gidip gelerek kullanmanın (çıkmaz sokak sapı) en uzun hâli (metre).
    var maxRepeatedStretch = 120.0

    // MARK: Ağ

    /// Aynı anda uçan en fazla MKDirections isteği. Hızın asıl sınırı
    /// `requestPacing`; buradaki 3 yalnızca patlama kredisiyle giden isteklerin
    /// gecikmesini üst üste bindirir.
    var maxConcurrentRequests = 3
    /// Beklemesiz art arda gönderilebilecek istek sayısı (bkz. `RequestPacer`).
    /// 8: ilk tur tamamen, düzeltme turunun da bir kısmı beklemeden gider.
    var requestBurst = 8
    /// Patlama hakkı bitince ardışık istek başlangıçları arasındaki süre. Kota
    /// kısıtı: herhangi bir 60 sn'lik pencerede en fazla `requestBurst` + 60/süre
    /// istek gider; bu toplam (8 + 40 = 48) MapKit'in gözlemlenen throttle
    /// eşiğinin (~50/dk) altında kalmalı. Süreyi kısaltmak patlamayı büyütmekten
    /// daha az kazandırır: tipik üretimin çoğu isteği zaten patlama içinde.
    var requestPacing: Duration = .seconds(1.5)
    /// Bir üretimde GEÇİCİ ağ hatasından en fazla kaç kez toparlanılır.
    var maxRecoveries = 3
    /// İlk bekleme; her toparlanmada ikiye katlanır (1 s, 2 s, 4 s). Tek bir cihaz
    /// tek bir sunucuya istek attığı için jitter eklenmez: dağıtılacak kalabalık yok.
    var backoffBase: Duration = .seconds(1)
    /// Throttle'dan toparlanma hakkı: TEK. Throttle penceresi tipik olarak ~1 dk
    /// sürer; kısa üstel bekleme onu aşamaz. Tek uzun bekleme, patlama kenarındaki
    /// tekil throttle'ı affeder; ikinci throttle gerçek kota aşımı demektir ve ağ
    /// işi durdurulup eldeki en iyi adaya düşülür.
    var maxThrottleRecoveries = 1
    /// Throttle sonrası tek beklemenin süresi.
    var throttleBackoff: Duration = .seconds(10)
    /// Bu süreden sonra yeni döngü denemesi başlatılmaz, yedeğe geçilir. Yalnızca
    /// denemeler arasında bakılır: başlamış bir tur asla yarıda kesilmez. Hız
    /// sınırı (`requestPacing`) turları yavaşlatabildiği için süre geniş tutulur.
    var loopTimeLimit: Duration = .seconds(40)

    // MARK: Türetilen bütçe

    /// Bir döngü turunun en kötü maliyeti: her bacak + bir waypoint onarımı (2 bacak).
    var worstCaseLoopEvaluation: Int { vertexCountRange.upperBound + 2 }
    /// Git-gel turu: 2 bacak + onarım (2 bacak).
    var worstCaseFallbackEvaluation: Int { 4 }

    /// Döngü aşamasının istek bütçesi = (deneme × tur + toparlanmada tekrarlanan tur)
    /// × tur maliyeti. Sabit bir sayı değil, planın kendisinden türer: plan içindeki
    /// hiçbir iş bütçeye takılıp yarıda kalmaz. Bütçe yalnızca planın dışına taşan
    /// durumları sınırlar ve her tur, başlamadan önce kalan bütçeye sığıp
    /// sığmadığına bakar.
    var loopRequestBudget: Int {
        (maxLoopAttempts * maxEvaluations + maxRecoveries + maxThrottleRecoveries) * worstCaseLoopEvaluation
    }

    var fallbackRequestBudget: Int {
        (fallbackAttempts * maxEvaluations + maxRecoveries + maxThrottleRecoveries) * worstCaseFallbackEvaluation
    }

    var requestBudget: Int { loopRequestBudget + fallbackRequestBudget }

    /// `n`. toparlanmadan önceki bekleme (n ≥ 1).
    func backoff(forRecovery n: Int) -> Duration {
        backoffBase * (1 << max(n - 1, 0))
    }
}

/// Son üretimin ölçümleri: testlerde ve hata ayıklamada yakınsamayı görmek için.
nonisolated struct GenerationStats: Equatable {
    /// Ağa giden istek (throttle yiyenler dahil).
    var requests = 0
    /// Cache'ten karşılanan bacak.
    var cachedLegs = 0
    /// Yapılan yarıçap turu (tüm şekiller toplamı).
    var evaluations = 0
    /// Denenen şekil.
    var attempts = 0
    /// Throttle/ağ hatasından toparlanma.
    var recoveries = 0
}

// MARK: - Kalıcı dolambaç katsayısı

/// Öğrenilen dolambaç katsayılarını (`DetourEstimate.learnedFactors`) oturumlar
/// arasında saklar. Kalıcılık sayesinde bilinen bölgede ilk üretim bile çoğu
/// zaman tek turda biter: düzeltme turunun istekleri ve beklemesi atlanır.
protocol DetourStoring {
    func loadDetourFactors() -> [String: Double]
    func saveDetourFactors(_ factors: [String: Double])
}

extension UserDefaults: DetourStoring {
    private static let detourFactorsKey = "learnedDetourFactors"

    func loadDetourFactors() -> [String: Double] {
        dictionary(forKey: Self.detourFactorsKey) as? [String: Double] ?? [:]
    }

    func saveDetourFactors(_ factors: [String: Double]) {
        set(factors, forKey: Self.detourFactorsKey)
    }
}

// MARK: - Üretim motoru

/// Döngü rota üretim motoru: ağ katmanını (`LegFetcher`) ve saf geometriyi
/// (`LoopShape`, `RadiusSolver`, `RouteFootprint`) birleştirir; UI durumunu bilmez.
///
/// Akış: (1) farklı yönlere açılan birkaç döngü şekli; her biri için yarıçap
/// hedefe yakınsatılır. (2) Hiçbiri tam kabul edilmezse eşiklere en yakın döngü.
/// (3) O da yoksa git-gel rota. Ancak ağ tamamen çökerse hata fırlatılır.
///
/// Oturum boyunca yalnızca üç şey hatırlanır: son rotalar (çeşitlilik), öğrenilen
/// dolambaç katsayısı (yakınsama) ve bacak cache'i.
final class RouteGenerator {
    let policy: GenerationPolicy
    private(set) var lastStats = GenerationStats()

    private let fetcher: LegFetcher
    /// Üretimdeki tüm rastgele kararların tek kaynağı (bkz. `SeededRandom`).
    private var random: SeededRandom
    /// `nil` ise (testler) öğrenilenler yalnızca bu oturumda yaşar.
    private let detourStore: (any DetourStoring)?
    private var detour: DetourEstimate
    private var recentRoutes: [Remembered] = []
    private let historyLimit = 10
    /// Bu mesafeden yakın başlangıçlar "aynı yer" sayılır (metre).
    private let sameStartRadius = 250.0

    private struct Remembered {
        let start: CLLocationCoordinate2D
        let bearing: Double
        let footprint: RouteFootprint
    }

    init(
        provider: any DirectionsProviding = MapKitDirections(),
        policy: GenerationPolicy = GenerationPolicy(),
        seed: UInt64 = .random(in: .min ... .max),
        detourStore: (any DetourStoring)? = nil
    ) {
        self.policy = policy
        self.detourStore = detourStore
        self.detour = DetourEstimate(learnedFactors: detourStore?.loadDetourFactors() ?? [:])
        self.fetcher = LegFetcher(
            provider: provider,
            maxConcurrentRequests: policy.maxConcurrentRequests,
            requestBurst: policy.requestBurst,
            requestPacing: policy.requestPacing
        )
        self.random = SeededRandom(seed: seed)
    }

    // MARK: Genel kullanım

    /// Başlangıç noktasına dönen, hedef mesafeye yakın bir rota üretir.
    func generate(from start: CLLocationCoordinate2D, targetDistance target: Double) async throws -> GeneratedRoute {
        guard target > 0 else { throw RouteGenerationError.invalidDistance }
        fetcher.trimIfNeeded()

        var run = Run(start: start, target: target, deadline: .now + policy.loopTimeLimit, requestsAtStart: fetcher.requestCount)
        defer {
            run.stats.requests = fetcher.requestCount - run.requestsAtStart
            lastStats = run.stats
            detourStore?.saveDetourFactors(detour.learnedFactors)
        }

        // DETERMİNİSTİK: aynı yerden önceki rotalar varsa temel yön hepsine en uzak yön.
        // RASTGELE: geçmiş yoksa temel yön serbest.
        let base = BearingPlanner.leastUsedBearing(avoiding: recentBearings(near: start))
            ?? Double.random(in: 0..<360, using: &random)

        // 1) Döngü denemeleri.
        run.beginPhase(budget: policy.loopRequestBudget, requestCount: fetcher.requestCount)
        for attempt in 0..<policy.maxLoopAttempts {
            try Task.checkCancellation()
            guard run.networkFailure == nil, ContinuousClock.now < run.deadline else { break }

            let jitter = Double.random(in: -policy.bearingJitter...policy.bearingJitter, using: &random)
            let bearing = BearingPlanner.bearing(forAttempt: attempt, base: base, jitter: jitter)
            let shape = LoopShape.loop(openingBearing: bearing, vertexCountRange: policy.vertexCountRange, using: &random)
            run.stats.attempts += 1

            guard let route = try await fit(shape, kind: .loop, run: &run) else { continue }
            let footprint = RouteFootprint(Geo.joinedCoordinates(of: route.polylines))

            switch judge(route, footprint: footprint, start: start) {
            case .accept:
                return remember(route, footprint)
            case .relaxed(let penalty) where penalty < run.relaxed?.penalty ?? .infinity:
                run.relaxed = (route, footprint, penalty)
            case .relaxed, .reject:
                continue
            }
        }

        // 2) Eşiklere en yakın döngü: çoğunlukla yalnızca örtüşme yüzünden elenmiş bir aday.
        if let relaxed = run.relaxed {
            return remember(relaxed.route, relaxed.footprint)
        }

        // 3) Git-gel: iki bacak, gevşek tolerans. İlk kullanımda (geçmiş yokken)
        // döngü çıkmasa bile kullanıcı "rota bulunamadı" görmez.
        run.beginPhase(budget: policy.fallbackRequestBudget, requestCount: fetcher.requestCount)
        for attempt in 0..<policy.fallbackAttempts where run.networkFailure == nil {
            try Task.checkCancellation()
            let bearing = BearingPlanner.bearing(forAttempt: attempt, base: base, jitter: 0)
            run.stats.attempts += 1

            guard let route = try await fit(.outAndBack(bearing: bearing), kind: .outAndBack, run: &run),
                  abs(route.distanceError) <= policy.fallbackTolerance else { continue }
            return remember(route, RouteFootprint(Geo.joinedCoordinates(of: route.polylines)))
        }

        throw run.networkFailure ?? .noWalkableRoute
    }

    // MARK: Yakınsama döngüsü

    /// Bir şeklin yarıçapını `RadiusSolver` ile hedefe yakınsatır. Hedefe en yakın
    /// rotayı, şekil hiç kullanılamazsa `nil` döner.
    private func fit(_ initialShape: LoopShape, kind: GeneratedRoute.Kind, run: inout Run) async throws -> GeneratedRoute? {
        var shape = initialShape
        var solver = RadiusSolver(
            target: run.target,
            initialRadius: shape.initialRadius(target: run.target, detourFactor: detour.factor(near: run.start)),
            tolerance: policy.tolerance,
            maxEvaluations: policy.maxEvaluations
        )
        var previous: [CLLocationCoordinate2D]?
        var best: GeneratedRoute?
        var isRepaired = false

        while let radius = solver.nextRadius {
            let waypoints = LoopShape.pin(
                shape.waypoints(from: run.start, radius: radius),
                to: previous,
                tolerance: policy.pinTolerance
            )

            switch try await evaluate(waypoints, run: &run) {
            case .aborted:
                return best

            case .unusable(let indices):
                // Şekil başına tek onarım: waypoint pivota çekilip AYNI yarıçap tekrar
                // denenir. Yalnızca o waypoint'in iki bacağı yeniden istenir, kalanlar
                // cache'ten gelir. Birden fazla waypoint kötüyse şekil o yöne uygun
                // değildir; ısrar etmek yerine sıradaki yöne geçilir.
                guard !isRepaired, indices.count == 1 else { return best }
                isRepaired = true
                shape = shape.pullingIn(waypoint: indices[0], by: policy.repairPull)
                previous = waypoints

            case .route(let legs):
                let distance = legs.reduce(0) { $0 + $1.distance }
                solver.record(radius: radius, distance: distance)
                detour.observe(distance / straightPerimeter([run.start] + waypoints), at: run.start)
                previous = waypoints

                let route = GeneratedRoute(
                    start: run.start,
                    legs: legs,
                    distance: distance,
                    targetDistance: run.target,
                    kind: kind,
                    bearing: shape.openingBearing
                )
                if best.map({ abs(route.distanceError) < abs($0.distanceError) }) ?? true {
                    best = route
                }
            }
        }
        return best
    }

    private enum Evaluation {
        case route([MKRoute])
        /// Yürünemeyen waypoint'lerin `waypoints` içindeki sıraları.
        case unusable([Int])
        /// Bütçe ya da toparlanma hakkı bitti; bu şekil bırakılır.
        case aborted
    }

    /// Verilen waypoint'lerle döngünün bütün bacaklarını çeker ve doğrular.
    private func evaluate(_ waypoints: [CLLocationCoordinate2D], run: inout Run) async throws -> Evaluation {
        let ring = [run.start] + waypoints

        // Maliyet istekten ÖNCE bilinir: tur (olası onarımı dahil) kalan bütçeye
        // sığmıyorsa hiç başlatılmaz. Yarıda kesilen bir tur boşa harcanmış istektir.
        let cost = fetcher.missingCount(around: ring)
        guard cost + 2 <= run.remainingBudget(requestCount: fetcher.requestCount) else { return .aborted }
        run.stats.evaluations += 1
        run.stats.cachedLegs += ring.count - cost

        guard try await prefetch(ring, run: &run) else { return .aborted }

        var routes: [MKRoute] = []
        var unusable: Set<Int> = []
        for (index, leg) in fetcher.legs(around: ring).enumerated() {
            // legs[i]: ring[i] → ring[i + 1]; son bacak başa döner. ring[k] = waypoints[k - 1].
            let destination = (index + 1) % ring.count
            guard case .route(let route)? = leg else {
                // Yol yok: hedef bir waypoint'se suç onun; hedef başlangıçsa kaynağın.
                unusable.insert((destination == 0 ? index : destination) - 1)
                continue
            }
            // MapKit waypoint'i uzaktaki bir yola bağladıysa orası yürünebilir değil.
            // Başlangıç kontrol edilmez: kullanıcı parkın ortasında olabilir, taşınamaz.
            if destination != 0,
               let end = Geo.lastCoordinate(of: route.polyline),
               Geo.distance(end, ring[destination]) > policy.maxSnapDistance {
                unusable.insert(destination - 1)
            }
            routes.append(route)
        }
        return unusable.isEmpty ? .route(routes) : .unusable(unusable.sorted())
    }

    /// Eksik bacakları çeker. Hatada o turun kuyruktaki istekleri iptal edilir,
    /// beklenir ve tur KALDIĞI YERDEN sürer: gelmiş bacaklar cache'te olduğu için
    /// yalnızca eksikler yeniden istenir. Geçici ağ hatasında üstel bekleme ile
    /// `maxRecoveries` kez denenir; throttle'da yalnızca tek uzun bekleme hakkı
    /// vardır (`throttleBackoff`), çünkü throttle penceresi kısa beklemelerle
    /// aşılamaz. Haklar bitince ağ işi durur ve eldeki en iyi sonuca düşülür.
    private func prefetch(_ ring: [CLLocationCoordinate2D], run: inout Run) async throws -> Bool {
        while true {
            do {
                try await fetcher.prefetch(around: ring)
                return true
            } catch let failure as DirectionsFailure {
                switch failure {
                case .throttled:
                    guard run.throttleRecoveries < policy.maxThrottleRecoveries else {
                        run.networkFailure = .rateLimited
                        return false
                    }
                    run.throttleRecoveries += 1
                    run.stats.recoveries += 1
                    try await Task.sleep(for: policy.throttleBackoff)
                case .unavailable:
                    guard run.networkRecoveries < policy.maxRecoveries else {
                        run.networkFailure = .networkUnavailable
                        return false
                    }
                    run.networkRecoveries += 1
                    run.stats.recoveries += 1
                    try await Task.sleep(for: policy.backoff(forRecovery: run.networkRecoveries))
                }
            }
        }
    }

    // MARK: Değerlendirme

    private enum Verdict {
        case accept
        /// Eşiklerin dışında ama yedek olabilir; ceza eşiklerin ne kadar aşıldığı.
        case relaxed(penalty: Double)
        case reject
    }

    private func judge(_ route: GeneratedRoute, footprint: RouteFootprint, start: CLLocationCoordinate2D) -> Verdict {
        let error = abs(route.distanceError)
        guard error <= policy.fallbackTolerance else { return .reject }

        // Aynı sokağı gidip gelen döngü iyi bir döngü değil; yedek olarak bile tutulmaz.
        let repeated = footprint.longestRepeatedStretch(excluding: start, startZone: policy.startZone)
        guard repeated <= policy.maxRepeatedStretch else { return .reject }

        let overlap = recentFootprints(near: start).map {
            footprint.overlap(with: $0, corridor: policy.overlapCorridor, excluding: start, startZone: policy.startZone)
        }.max() ?? 0

        if error <= policy.acceptance, overlap <= policy.maxOverlap { return .accept }
        return .relaxed(penalty: max(0, error - policy.acceptance) + max(0, overlap - policy.maxOverlap))
    }

    // MARK: Geçmiş

    private func remember(_ route: GeneratedRoute, _ footprint: RouteFootprint) -> GeneratedRoute {
        recentRoutes.append(Remembered(start: route.start, bearing: route.bearing, footprint: footprint))
        if recentRoutes.count > historyLimit { recentRoutes.removeFirst() }
        return route
    }

    private func recentBearings(near start: CLLocationCoordinate2D) -> [Double] {
        recentRoutes.filter { Geo.distance($0.start, start) < sameStartRadius }.map(\.bearing)
    }

    private func recentFootprints(near start: CLLocationCoordinate2D) -> [RouteFootprint] {
        recentRoutes
            .filter { Geo.distance($0.start, start) < sameStartRadius }
            .suffix(policy.diversityWindow)
            .map(\.footprint)
    }

    private func straightPerimeter(_ ring: [CLLocationCoordinate2D]) -> Double {
        ring.indices.reduce(0) { $0 + Geo.distance(ring[$1], ring[($1 + 1) % ring.count]) }
    }

    // MARK: Çağrı defteri

    /// Tek bir `generate` çağrısının durumu. Paylaşılan durumdan ayrı tutulur ki
    /// iptal edilmiş eski bir çağrı, yenisinin sayaçlarını bozmasın.
    private struct Run {
        let start: CLLocationCoordinate2D
        let target: Double
        let deadline: ContinuousClock.Instant
        let requestsAtStart: Int
        var stats = GenerationStats()
        /// Geçici ağ hatasından toparlanma sayısı (sınır: `maxRecoveries`).
        var networkRecoveries = 0
        /// Throttle'dan toparlanma sayısı (sınır: `maxThrottleRecoveries`).
        var throttleRecoveries = 0
        /// Toparlanma hakkı bitince ağ işi durur; sebep burada.
        var networkFailure: RouteGenerationError?
        var relaxed: (route: GeneratedRoute, footprint: RouteFootprint, penalty: Double)?
        private var phaseBudget = 0
        private var phaseStart = 0

        init(start: CLLocationCoordinate2D, target: Double, deadline: ContinuousClock.Instant, requestsAtStart: Int) {
            self.start = start
            self.target = target
            self.deadline = deadline
            self.requestsAtStart = requestsAtStart
        }

        mutating func beginPhase(budget: Int, requestCount: Int) {
            phaseBudget = budget
            phaseStart = requestCount
        }

        func remainingBudget(requestCount: Int) -> Int {
            phaseBudget - (requestCount - phaseStart)
        }
    }
}
