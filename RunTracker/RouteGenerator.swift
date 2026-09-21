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
    /// Üst sınır 6: köşe sayısı arttıkça döngü daha çok sokağa uğrar, yani
    /// çeşitlilik artar. Tipik üretim artık tek tur sürdüğü (bkz. `acceptance`)
    /// için fazladan köşe patlama kredisinin içinde kalıyor.
    var vertexCountRange = 4...6
    /// Açılış yönüne eklenen sapmanın EN AZI (± derece). Serbest yay genişse
    /// sapma `maxBearingJitter`'a kadar açılır; bkz. `BearingPlanner.leastUsed`.
    var bearingJitter = 20.0
    /// Sapmanın üst sınırı (± derece): serbest yay ne kadar genişse genişlesin
    /// temel yönden bu kadar uzaklaşılır, yoksa "en uzak yön" seçimi anlamsızlaşır.
    var maxBearingJitter = 60.0

    // MARK: Yakınsama

    /// Sapma bunun altına inince yarıçap düzeltmesi durur (±%10).
    var tolerance = 0.10
    /// Döngünün doğrudan kabul edildiği en büyük sapma (±%20). Genişçe tutulur:
    /// ilk tahmin ne kadar sık kabul edilirse düzeltme turunun istekleri o kadar
    /// sık atlanır; hem kota hem bekleme süresi kazanılır. Bu eşik her turun
    /// SONUNDA uygulanır (bkz. `fit`): kabul edilebilir rota bulunduğu anda
    /// yakınsama durur.
    var acceptance = 0.20
    /// Yedeklerin (gevşek döngü, git-gel) kabul sınırı (±%25).
    var fallbackTolerance = 0.25
    /// Bir şekil için en fazla yarıçap turu: 1 ilk tahmin + 2 düzeltme. Orantısal
    /// düzeltme tipik olarak 1 düzeltmede ±%10'a indiği için 2'si pay bırakır.
    var maxEvaluations = 3
    /// Kaç farklı döngü şekli için AĞA GİDİLİR.
    var maxLoopAttempts = 4
    /// Kaç farklı döngü şekli ÜRETİLİP bakılır. Aradaki fark bedava elenenlere
    /// ayrılmıştır (bkz. `maxSkeletonOverlap`): iskeleti son rotaların kopyası
    /// olan şekil, deneme hakkı harcamadan atlanır.
    var maxShapeCandidates = 10
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
    /// Kuş uçuşu iskelet, son rotalardan birinin koridoruna bu orandan fazla
    /// oturuyorsa şekil AĞA HİÇ GİDİLMEDEN elenir.
    ///
    /// Eskiden benzerlik ancak bacaklar çekildikten sonra anlaşılıyor, elenen her
    /// deneme 4–6 isteği (ve saniyelerce beklemeyi) çöpe atıyordu. Eşik temkinli
    /// (yüksek) tutulur: eleme bedava olduğu için yalnızca bariz kopyaları kesmesi
    /// yeter, meşru bir şekli yanlışlıkla elemek ise gerçek bir kayıptır.
    var maxSkeletonOverlap = 0.75
    /// İskelet karşılaştırmasının koridoru (metre). `overlapCorridor`'dan geniş:
    /// iskelet düz çizgilerden oluşur, gerçek rota ise sokakları takip eder.
    var skeletonCorridor = 50.0
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
    /// 16: tipik bir üretimin (bir şekil, bir tur, 4–6 bacak) TAMAMI ve arkasından
    /// bir düzeltme turu daha beklemesiz gider. Kritik olan bu: sıradan üretim
    /// patlamanın içinde kalırsa süreyi ağ gecikmesi belirler, hız sınırı değil.
    var requestBurst = 16
    /// Patlama hakkı bitince ardışık istek başlangıçları arasındaki süre. Kota
    /// kısıtı: herhangi bir 60 sn'lik pencerede en fazla `requestBurst` + 60/süre
    /// istek gider; bu toplam (16 + 30 = 46) MapKit'in gözlemlenen throttle
    /// eşiğinin (~50/dk) altında kalmalı. Patlamayı büyütüp aralığı uzatmak,
    /// aynı dakikalık toplamı sıradan üretimin lehine dağıtır.
    var requestPacing: Duration = .seconds(2)
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
    /// Döngü aşamasının süre sınırı: dolunca ne yeni deneme ne de yeni DÜZELTME
    /// turu başlatılır, yedeğe geçilir. Başlamış bir tur asla yarıda kesilmez.
    var loopTimeLimit: Duration = .seconds(40)
    /// Yedek aşamasının kendi süre sınırı. Eskiden yedek aşamada hiç süre
    /// kontrolü yoktu: döngü aşaması süresini doldurduktan SONRA yedek bir yarım
    /// dakika daha ekleyebiliyordu. İkisinin toplamı algılanan en kötü süredir.
    var fallbackTimeLimit: Duration = .seconds(20)

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

// MARK: - Kalıcı bellek

/// Üretimin oturumlar arasında hatırladıkları.
///
/// İkisi de aynı amaca hizmet eder: uygulama yeniden açıldığında üretim sıfırdan
/// başlamasın. Dolambaç katsayısı ilk yarıçap tahminini tutturur (hız); rota
/// geçmişi yeni rotanın eskilerden farklı bir yöne açılmasını sağlar (çeşitlilik).
/// Eskiden yalnızca ilki saklanıyordu, bu yüzden her açılışta ilk rota önceki
/// oturumunkinin kopyası olabiliyordu.
protocol GenerationStoring {
    func loadDetourFactors() -> [String: Double]
    func saveDetourFactors(_ factors: [String: Double])
    /// Son rotaların kodlanmış hâli; biçim için bkz. `RouteGenerator.Remembered`.
    func loadRouteHistory() -> [[Double]]
    func saveRouteHistory(_ history: [[Double]])
}

extension UserDefaults: GenerationStoring {
    private static let detourFactorsKey = "learnedDetourFactors"
    private static let routeHistoryKey = "recentRouteFootprints"

    func loadDetourFactors() -> [String: Double] {
        dictionary(forKey: Self.detourFactorsKey) as? [String: Double] ?? [:]
    }

    func saveDetourFactors(_ factors: [String: Double]) {
        set(factors, forKey: Self.detourFactorsKey)
    }

    func loadRouteHistory() -> [[Double]] {
        array(forKey: Self.routeHistoryKey) as? [[Double]] ?? []
    }

    func saveRouteHistory(_ history: [[Double]]) {
        set(history, forKey: Self.routeHistoryKey)
    }
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
    private struct Remembered {
        /// Kalıcı biçimde örneklerin seyreltme oranı. İz zaten 10 m'ye yeniden
        /// örneklendiği ve koridor testi 25 m olduğu için 40 m'lik örnekler
        /// sonucu değiştirmez, saklanan veriyi dörtte birine indirir.
        static let sampleStride = 4

        let start: CLLocationCoordinate2D
        let bearing: Double
        let footprint: RouteFootprint

        init(start: CLLocationCoordinate2D, bearing: Double, footprint: RouteFootprint) {
            self.start = start
            self.bearing = bearing
            self.footprint = footprint
        }

        /// Kalıcı biçim: [başlangıç enlem, boylam, yön, örnek enlem, örnek boylam, …].
        /// Düz bir `Double` dizisi olduğu için dönüştürülmeden plist'e yazılır.
        var encoded: [Double] {
            var values = [start.latitude, start.longitude, bearing]
            for index in stride(from: 0, to: footprint.samples.count, by: Self.sampleStride) {
                values.append(footprint.samples[index].latitude)
                values.append(footprint.samples[index].longitude)
            }
            return values
        }

        init?(encoded values: [Double]) {
            // 3 başlık + çift sayıda koordinat bileşeni ⇒ toplam tek sayı.
            guard values.count >= 7, values.count % 2 == 1 else { return nil }
            var samples: [CLLocationCoordinate2D] = []
            for index in stride(from: 3, to: values.count, by: 2) {
                samples.append(CLLocationCoordinate2D(latitude: values[index], longitude: values[index + 1]))
            }
            self.start = CLLocationCoordinate2D(latitude: values[0], longitude: values[1])
            self.bearing = values[2]
            self.footprint = RouteFootprint(samples)
        }
    }

    /// Ölçülmüş bir rota ve izi. İz her turda bir kez kurulur; hem yargı hem
    /// geçmiş aynı nesneyi kullanır.
    private struct Candidate {
        let route: GeneratedRoute
        let footprint: RouteFootprint
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
        self.recentRoutes = Array((store?.loadRouteHistory() ?? []).compactMap(Remembered.init(encoded:)).suffix(Self.historyLimit))
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

        var run = Run(start: start, target: target, deadline: .now + policy.loopTimeLimit, requestsAtStart: fetcher.requestCount)
        defer {
            run.stats.requests = fetcher.requestCount - run.requestsAtStart
            lastStats = run.stats
            save()
        }

        // DETERMİNİSTİK: aynı yerden önceki rotalar varsa temel yön hepsine en uzak
        // yön. RASTGELE: geçmiş yoksa temel yön serbest.
        let plan = BearingPlanner.leastUsed(avoiding: recentBearings(near: start))
        let base = plan?.bearing ?? Double.random(in: 0..<360, using: &random)
        // Sapma payı serbest yayın yarısı kadar açılır (en az `bearingJitter`, en
        // çok `maxBearingJitter`). Tek bir önceki rota varken ters yönde 180°'lik
        // boşluk vardır; sabit ±20° ile hep o boşluğun ortasına çakmak, aynı yerden
        // aynı mesafeyi isteyen kullanıcıya hep aynı rotayı veriyordu.
        let spread = min(max(policy.bearingJitter, (plan?.clearance ?? 180) / 2), policy.maxBearingJitter)
        let recent = recentFootprints(near: start)

        // 1) Döngü denemeleri.
        run.beginPhase(budget: policy.loopRequestBudget, requestCount: fetcher.requestCount)
        var attempts = 0
        var candidates = 0
        while attempts < policy.maxLoopAttempts, candidates < policy.maxShapeCandidates {
            try Task.checkCancellation()
            guard run.networkFailure == nil, ContinuousClock.now < run.deadline else { break }

            let jitter = Double.random(in: -spread...spread, using: &random)
            let bearing = BearingPlanner.bearing(forAttempt: candidates, base: base, jitter: jitter)
            let shape = LoopShape.loop(openingBearing: bearing, vertexCountRange: policy.vertexCountRange, using: &random)
            let radius = shape.initialRadius(target: target, detourFactor: detour.factor(near: start, bearing: bearing))
            candidates += 1

            // BEDAVA ELEME: iskelet son rotaların koridorundan geçiyorsa bu şekil
            // neredeyse kopya çıkar. Deneme hakkı harcanmaz — ağa gidilmediği için
            // harcanacak bir şey yok; yalnızca sıradaki yöne geçilir.
            //
            // Eleme yalnızca BOŞLUKTAN yer: kalan aday hakkı kalan deneme hakkına
            // inince kapanır, yani `maxLoopAttempts` gerçek deneme her hâlükârda
            // yapılır. Aksi halde çevresindeki her yönü kullanmış bir kullanıcıda
            // tüm adaylar elenir, döngü aşaması ağa hiç gitmeden biter ve hafifçe
            // örtüşen bir döngü yerine aynı yolu iki kez yürüten git-gel rotası
            // verilirdi — çeşitlilik adına daha tekrarlı bir sonuç.
            if policy.maxShapeCandidates - candidates >= policy.maxLoopAttempts - attempts,
               isNearDuplicate(shape, radius: radius, start: start, recent: recent) {
                run.stats.skippedShapes += 1
                continue
            }

            attempts += 1
            run.stats.attempts += 1
            onProgress(GenerationProgress(attempt: attempts, maxAttempts: policy.maxLoopAttempts))

            let outcome = try await fit(shape, radius: radius, kind: .loop, run: &run) { [self] route, footprint in
                judge(route, footprint: footprint, start: start, recent: recent)
            }
            if let accepted = outcome.accepted { return remember(accepted) }
            if let relaxed = outcome.relaxed, relaxed.penalty < run.relaxed?.penalty ?? .infinity {
                run.relaxed = relaxed
            }
        }

        // 2) Eşiklere en yakın döngü: çoğunlukla yalnızca örtüşme yüzünden elenmiş bir aday.
        if let relaxed = run.relaxed {
            return remember(Candidate(route: relaxed.route, footprint: relaxed.footprint))
        }

        // 3) Git-gel: iki bacak, gevşek tolerans. İlk kullanımda (geçmiş yokken)
        // döngü çıkmasa bile kullanıcı "rota bulunamadı" görmez.
        run.beginPhase(budget: policy.fallbackRequestBudget, requestCount: fetcher.requestCount)
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
                    distance / straightPerimeter([run.start] + waypoints),
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
                let footprint = RouteFootprint(Geo.joinedCoordinates(of: route.polylines))

                switch verdict(route, footprint) {
                case .accept:
                    result.accepted = Candidate(route: route, footprint: footprint)
                    return result
                case .relaxed(let penalty) where penalty < result.relaxed?.penalty ?? .infinity:
                    result.relaxed = (route, footprint, penalty)
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
        var relaxed: (route: GeneratedRoute, footprint: RouteFootprint, penalty: Double)?
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
        store.saveRouteHistory(recentRoutes.map(\.encoded))
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
        /// Aşamanın bitiş anı; aşama değişince (döngü → yedek) yenilenir.
        var deadline: ContinuousClock.Instant
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
