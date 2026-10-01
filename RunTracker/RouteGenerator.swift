//
//  RouteGenerator.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 15.09.2026.
//

import Foundation
import MapKit
import CoreLocation

/// Son üretimin ölçümleri: testlerde ve hata ayıklamada yakınsamayı görmek için.
nonisolated struct GenerationStats: Equatable {
    /// Ağa giden istek (throttle yiyenler dahil).
    var requests = 0
    /// Yapılan yarıçap turu (tüm şekiller toplamı).
    var evaluations = 0
    /// Ağa gidilen şekil.
    var attempts = 0
    /// Ağa hiç gidilmeden, iskelet benzerliği yüzünden elenen şekil.
    var skippedShapes = 0
    /// Throttle/ağ hatasından toparlanma.
    var recoveries = 0
}

/// Üretim sürerken UI'a bildirilen ilerleme. Kullanıcı bir ilerleme çubuğu
/// yerine boş bir spinner gördüğünde bekleme olduğundan uzun hissedilir.
nonisolated struct GenerationProgress: Equatable {
    /// Kaçıncı şekil deneniyor (1'den başlar).
    var attempt: Int
    /// Bu aşamada denenecek en fazla şekil.
    var maxAttempts: Int
    /// Döngü bulunamadı, git-gel yedeğine geçildi.
    var isFallback = false
}

// MARK: - Üretim motoru

/// Döngü rota üretim motoru: ağ katmanını (`LegFetcher`) ve saf geometriyi
/// (`LoopShape`, `RadiusSolver`, `RouteFootprint`) birleştirir; UI durumunu bilmez.
///
/// Akış: (1) farklı yönlere açılan birkaç döngü şekli; her biri için yarıçap
/// hedefe yakınsatılır ve HER TURUN sonunda aday yargılanır — kabul edilen ilk
/// aday hemen döner. (2) Hiçbiri kabul edilmezse eşiklere en yakın döngü.
/// (3) O da yoksa git-gel rota. Ancak ağ tamamen çökerse hata fırlatılır.
///
/// Motor uygulamada TEKTİR (bkz. `RouteViewModel`): hız sınırı, bacak cache'i ve
/// rota geçmişi paylaşılmazsa her kopya MapKit kotasını ayrı ayrı harcar ve
/// birbirinin ürettiği rotadan habersiz kalır.
final class RouteGenerator {
    let policy: GenerationPolicy
    private(set) var lastStats = GenerationStats()

    private let fetcher: LegFetcher
    /// Üretimdeki tüm rastgele kararların tek kaynağı (bkz. `SeededRandom`).
    private var random: SeededRandom
    /// `nil` ise (testler) öğrenilenler yalnızca bu oturumda yaşar.
    private let store: (any GenerationStoring)?
    private var detour: DetourEstimate
    private var recentRoutes: [Remembered] = []
    /// Kaç rota hatırlanır. Geniş tutmanın anlamı yok: her yön "kullanılmış"
    /// sayılınca `BearingPlanner` seçecek yer bulamaz.
    private static let historyLimit = 6
    /// Bu mesafeden yakın başlangıçlar "aynı yer" sayılır (metre).
    private let sameStartRadius = 250.0

    /// Hatırlanan bir rota: yönü (sıradaki rotayı başka yöne açmak için) ve izi
    /// (sıradaki rotanın aynı sokaklara girmediğini doğrulamak için).
    private nonisolated struct Remembered {
        /// Kalıcı biçimde örneklerin seyreltme oranı. İz zaten 10 m'ye yeniden
        /// örneklendiği ve koridor testi 25 m olduğu için 40 m'lik örnekler
        /// sonucu değiştirmez, saklanan veriyi dörtte birine indirir.
        static let sampleStride = 4

        let start: CLLocationCoordinate2D
        let bearing: Double
        let footprint: RouteFootprint

        /// Saklanan biçim (bkz. `GenerationStoring`).
        var entry: RouteHistoryEntry {
            RouteHistoryEntry(
                start: RoutePoint(start),
                bearing: bearing,
                samples: stride(from: 0, to: footprint.samples.count, by: Self.sampleStride)
                    .map { RoutePoint(footprint.samples[$0]) }
            )
        }

        static func restoring(_ entry: RouteHistoryEntry) -> Remembered {
            Remembered(
                start: entry.start.coordinate,
                bearing: entry.bearing,
                footprint: RouteFootprint(entry.samples.map(\.coordinate))
            )
        }
    }

    /// Ölçülmüş bir rota ve izi. İz her turda bir kez kurulur; hem yargı hem
    /// geçmiş aynı nesneyi kullanır.
    private struct Candidate {
        let route: GeneratedRoute
        let footprint: RouteFootprint
        /// Eşiklerin ne kadar aşıldığı; kabul edilen adayda 0. Yedekler
        /// arasından en düşük cezalı olan seçilir.
        var penalty = 0.0
    }

    init(
        provider: any DirectionsProviding = MapKitDirections(),
        policy: GenerationPolicy = GenerationPolicy(),
        seed: UInt64 = .random(in: .min ... .max),
        store: (any GenerationStoring)? = nil
    ) {
        self.policy = policy
        self.store = store
        self.detour = DetourEstimate(learnedFactors: store?.loadDetourFactors() ?? [:])
        self.recentRoutes = (store?.loadRouteHistory() ?? []).suffix(Self.historyLimit).map(Remembered.restoring)
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
    func generate(
        from start: CLLocationCoordinate2D,
        targetDistance target: Double,
        onProgress: (GenerationProgress) -> Void = { _ in }
    ) async throws -> GeneratedRoute {
        guard target > 0 else { throw RouteGenerationError.invalidDistance }
        fetcher.trimIfNeeded()

        var run = Run(start: start, target: target, deadline: .now + policy.loopTimeLimit)
        let requestsAtStart = fetcher.requestCount
        defer {
            run.stats.requests = fetcher.requestCount - requestsAtStart
            lastStats = run.stats
            save()
        }

        let nearby = recentRoutes.filter { Geo.distance($0.start, start) < sameStartRadius }
        // DETERMİNİSTİK: aynı yerden önceki rotalar varsa temel yön hepsine en uzak
        // yön. RASTGELE: geçmiş yoksa temel yön serbest.
        let plan = BearingPlanner.leastUsed(avoiding: nearby.map(\.bearing))
        let base = plan?.bearing ?? Double.random(in: 0..<360, using: &random)
        // Sapma payı serbest yayın yarısı kadar açılır (en az `bearingJitter`, en
        // çok `maxBearingJitter`). Tek bir önceki rota varken ters yönde 180°'lik
        // boşluk vardır; sabit ±20° ile hep o boşluğun ortasına çakmak, aynı yerden
        // aynı mesafeyi isteyen kullanıcıya hep aynı rotayı veriyordu.
        let spread = min(max(policy.bearingJitter, (plan?.clearance ?? 180) / 2), policy.maxBearingJitter)
        let recent = nearby.suffix(policy.diversityWindow).map(\.footprint)

        // 1) Döngü denemeleri.
        var schedule = ShapeSchedule(maxAttempts: policy.maxLoopAttempts, maxCandidates: policy.maxShapeCandidates)
        while schedule.hasNext {
            try Task.checkCancellation()
            guard run.networkFailure == nil, ContinuousClock.now < run.deadline else { break }

            let jitter = Double.random(in: -spread...spread, using: &random)
            let bearing = BearingPlanner.bearing(forAttempt: schedule.nextCandidate(), base: base, jitter: jitter)
            let shape = LoopShape.loop(openingBearing: bearing, vertexCountRange: policy.vertexCountRange, using: &random)
            let radius = shape.initialRadius(target: target, detourFactor: detour.factor(near: start, bearing: bearing))

            // BEDAVA ELEME: iskelet son rotaların koridorundan geçiyorsa bu şekil
            // neredeyse kopya çıkar. Deneme hakkı harcanmaz — ağa gidilmediği için
            // harcanacak bir şey yok; yalnızca sıradaki yöne geçilir. Elemenin
            // neden yalnızca boşluktan yediği: bkz. `ShapeSchedule`.
            if schedule.canSkip, isNearDuplicate(shape, radius: radius, start: start, recent: recent) {
                run.stats.skippedShapes += 1
                continue
            }

            let attempt = schedule.recordAttempt()
            run.stats.attempts += 1
            onProgress(GenerationProgress(attempt: attempt, maxAttempts: policy.maxLoopAttempts))

            let outcome = try await fit(shape, radius: radius, kind: .loop, run: &run) { [self] route, footprint in
                judge(route, footprint: footprint, start: start, recent: recent)
            }
            if let accepted = outcome.accepted { return remember(accepted) }
            if let relaxed = outcome.relaxed, relaxed.penalty < run.relaxed?.penalty ?? .infinity {
                run.relaxed = relaxed
            }
        }

        // 2) Eşiklere en yakın döngü: çoğunlukla yalnızca örtüşme yüzünden elenmiş bir aday.
        if let relaxed = run.relaxed { return remember(relaxed) }

        // 3) Git-gel: iki bacak, gevşek tolerans. İlk kullanımda (geçmiş yokken)
        // döngü çıkmasa bile kullanıcı "rota bulunamadı" görmez.
        run.deadline = .now + policy.fallbackTimeLimit
        for attempt in 0..<policy.fallbackAttempts {
            try Task.checkCancellation()
            guard run.networkFailure == nil, ContinuousClock.now < run.deadline else { break }

            let bearing = BearingPlanner.bearing(forAttempt: attempt, base: base, jitter: 0)
            let shape = LoopShape.outAndBack(bearing: bearing)
            let radius = shape.initialRadius(target: target, detourFactor: detour.factor(near: start, bearing: bearing))
            run.stats.attempts += 1
            onProgress(GenerationProgress(attempt: attempt + 1, maxAttempts: policy.fallbackAttempts, isFallback: true))

            let outcome = try await fit(shape, radius: radius, kind: .outAndBack, run: &run) { [self] route, _ in
                abs(route.distanceError) <= policy.fallbackTolerance ? .accept : .reject
            }
            if let accepted = outcome.accepted { return remember(accepted) }
        }

        throw run.networkFailure ?? .noWalkableRoute
    }

    // MARK: Yakınsama döngüsü

    /// Bir şeklin yarıçapını `RadiusSolver` ile hedefe yakınsatır ve her turun
    /// sonunda adayı `verdict` ile yargılar.
    ///
    /// **Erken çıkış.** Kabul edilen ilk aday anında döner; kalan düzeltme
    /// turlarının istekleri hiç gönderilmez. Eskiden yakınsama önce `tolerance`a
    /// (±%10) kadar zorlanır, kabul eşiğine (`acceptance`, ±%20) ancak şekil
    /// bittikten sonra bakılırdı: elde kabul edilebilir bir rota varken iki tur
    /// daha, yani bacak sayısının iki katı kadar istek atılıyordu.
    private func fit(
        _ initialShape: LoopShape,
        radius initialRadius: Double,
        kind: GeneratedRoute.Kind,
        run: inout Run,
        verdict: (GeneratedRoute, RouteFootprint) -> Verdict
    ) async throws -> Fit {
        var shape = initialShape
        var solver = RadiusSolver(
            target: run.target,
            initialRadius: initialRadius,
            tolerance: policy.tolerance,
            maxEvaluations: policy.maxEvaluations
        )
        var previous: [CLLocationCoordinate2D]?
        var result = Fit()
        var isRepaired = false

        while let radius = solver.nextRadius {
            // Başlamış tur asla yarıda kesilmez ama YENİ bir tur için süre kalmalı.
            // Süre eskiden yalnızca denemeler arasında bakılıyordu; tek bir şekil
            // sınırsızca üç tur harcayabiliyor, süre sınırı da bir turun tamamını
            // aşabiliyordu.
            if !solver.samples.isEmpty, ContinuousClock.now >= run.deadline { break }

            let waypoints = LoopShape.pin(
                shape.waypoints(from: run.start, radius: radius),
                to: previous,
                tolerance: policy.pinTolerance
            )

            switch try await evaluate(waypoints, run: &run) {
            case .aborted:
                return result

            case .unusable(let indices):
                // Şekil başına tek onarım: waypoint pivota çekilip AYNI yarıçap tekrar
                // denenir. Yalnızca o waypoint'in iki bacağı yeniden istenir, kalanlar
                // cache'ten gelir. Birden fazla waypoint kötüyse şekil o yöne uygun
                // değildir; ısrar etmek yerine sıradaki yöne geçilir.
                guard !isRepaired, indices.count == 1 else { return result }
                isRepaired = true
                shape = shape.pullingIn(waypoint: indices[0], by: policy.repairPull)
                previous = waypoints

            case .route(let legs):
                let distance = legs.reduce(0) { $0 + $1.distance }
                solver.record(radius: radius, distance: distance)
                detour.observe(
                    distance / Geo.length(of: [run.start] + waypoints + [run.start]),
                    at: run.start,
                    bearing: shape.openingBearing
                )
                previous = waypoints

                let route = GeneratedRoute(
                    start: run.start,
                    legs: legs,
                    distance: distance,
                    targetDistance: run.target,
                    kind: kind,
                    bearing: shape.openingBearing
                )
                var candidate = Candidate(route: route, footprint: RouteFootprint(Geo.joinedCoordinates(of: route.polylines)))

                switch verdict(route, candidate.footprint) {
                case .accept:
                    result.accepted = candidate
                    return result
                case .relaxed(let penalty) where penalty < result.relaxed?.penalty ?? .infinity:
                    candidate.penalty = penalty
                    result.relaxed = candidate
                case .relaxed, .reject:
                    continue
                }
            }
        }
        return result
    }

    /// Bir şeklin tüm yarıçap turlarının sonucu.
    private struct Fit {
        /// Yargının kabul ettiği aday. Doluysa yakınsama erken bitmiştir.
        var accepted: Candidate?
        /// Eşiklerin dışında kalan en düşük cezalı aday.
        var relaxed: Candidate?
    }

    private enum Evaluation {
        case route([MKRoute])
        /// Yürünemeyen waypoint'lerin `waypoints` içindeki sıraları.
        case unusable([Int])
        /// Toparlanma hakkı bitti; bu şekil bırakılır.
        case aborted
    }

    /// Verilen waypoint'lerle döngünün bütün bacaklarını çeker ve doğrular.
    private func evaluate(_ waypoints: [CLLocationCoordinate2D], run: inout Run) async throws -> Evaluation {
        let ring = [run.start] + waypoints
        run.stats.evaluations += 1

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
    /// yalnızca eksikler yeniden istenir. Her hata türünün kendi toparlanma hakkı
    /// ve beklemesi vardır (bkz. `GenerationPolicy.recoveryLimit`): geçici ağ
    /// hatasında üstel bekleme, throttle'da tek uzun bekleme — throttle penceresi
    /// kısa beklemelerle aşılamaz. Haklar bitince ağ işi durur ve eldeki en iyi
    /// sonuca düşülür.
    private func prefetch(_ ring: [CLLocationCoordinate2D], run: inout Run) async throws -> Bool {
        while true {
            do {
                try await fetcher.prefetch(around: ring)
                return true
            } catch let failure as DirectionsFailure {
                let recovery = run.recoveries[failure, default: 0] + 1
                guard recovery <= policy.recoveryLimit(for: failure) else {
                    run.networkFailure = RouteGenerationError(failure)
                    return false
                }
                run.recoveries[failure] = recovery
                run.stats.recoveries += 1
                try await Task.sleep(for: policy.backoff(forRecovery: recovery, after: failure))
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

    private func judge(
        _ route: GeneratedRoute,
        footprint: RouteFootprint,
        start: CLLocationCoordinate2D,
        recent: [RouteFootprint]
    ) -> Verdict {
        let error = abs(route.distanceError)
        guard error <= policy.fallbackTolerance else { return .reject }

        // Aynı sokağı gidip gelen döngü iyi bir döngü değil; yedek olarak bile tutulmaz.
        let repeated = footprint.longestRepeatedStretch(excluding: start, startZone: policy.startZone)
        guard repeated <= policy.maxRepeatedStretch else { return .reject }

        let overlap = recent.map {
            footprint.overlap(with: $0, corridor: policy.overlapCorridor, excluding: start, startZone: policy.startZone)
        }.max() ?? 0

        if error <= policy.acceptance, overlap <= policy.maxOverlap { return .accept }
        return .relaxed(penalty: max(0, error - policy.acceptance) + max(0, overlap - policy.maxOverlap))
    }

    /// Şekil, ağa gidilmeden elenebilir mi? Kuş uçuşu iskelet son rotaların
    /// koridoruna oturuyorsa gerçek rota da büyük ihtimalle aynı sokaklardan
    /// geçecektir. Yanlış eleme pahalı (meşru bir rota kaybedilir), doğru eleme
    /// bedava olduğu için eşik temkinli tutulur: yalnızca bariz kopyalar.
    private func isNearDuplicate(
        _ shape: LoopShape,
        radius: Double,
        start: CLLocationCoordinate2D,
        recent: [RouteFootprint]
    ) -> Bool {
        guard !recent.isEmpty else { return false }
        let skeleton = RouteFootprint(shape.skeleton(from: start, radius: radius))
        return recent.contains {
            skeleton.overlap(
                with: $0,
                corridor: policy.skeletonCorridor,
                excluding: start,
                startZone: policy.startZone
            ) > policy.maxSkeletonOverlap
        }
    }

    // MARK: Geçmiş

    private func remember(_ candidate: Candidate) -> GeneratedRoute {
        recentRoutes.append(
            Remembered(start: candidate.route.start, bearing: candidate.route.bearing, footprint: candidate.footprint)
        )
        if recentRoutes.count > Self.historyLimit { recentRoutes.removeFirst() }
        return candidate.route
    }

    private func save() {
        guard let store else { return }
        store.saveDetourFactors(detour.learnedFactors)
        store.saveRouteHistory(recentRoutes.map(\.entry))
    }

    // MARK: Çağrı defteri

    /// Tek bir `generate` çağrısının durumu. Paylaşılan durumdan ayrı tutulur ki
    /// iptal edilmiş eski bir çağrı, yenisinin sayaçlarını bozmasın.
    private struct Run {
        let start: CLLocationCoordinate2D
        let target: Double
        /// Aşamanın bitiş anı; aşama değişince (döngü → yedek) yenilenir.
        var deadline: ContinuousClock.Instant
        var stats = GenerationStats()
        /// Hata türü başına toparlanma sayısı (sınır: `GenerationPolicy.recoveryLimit`).
        var recoveries: [DirectionsFailure: Int] = [:]
        /// Toparlanma hakkı bitince ağ işi durur; sebep burada.
        var networkFailure: RouteGenerationError?
        var relaxed: Candidate?
    }
}
