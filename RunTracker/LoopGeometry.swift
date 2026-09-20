//
//  LoopGeometry.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 15.09.2026.
//

import Foundation
import CoreLocation

// Bu dosyadaki her şey saf ve ağdan bağımsızdır: aynı girdi her zaman aynı
// çıktıyı verir, MapKit'e dokunmaz. Rota üretiminin "matematiği" (şekil,
// yarıçap yakınsaması, yön seçimi, rota benzerliği) burada; bu yüzden unit
// testlerde ağ olmadan doğrudan denenebilir.

// MARK: - Kontrollü rastgelelik

/// Tohumlanabilir rastgele sayı üreteci (SplitMix64).
///
/// Üretimdeki TÜM rastgele kararlar tek bir üreteçten çekilir. Uygulamada tohum
/// sistemden gelir (her istek farklı), testlerde sabit verilir: aynı tohum + aynı
/// ağ yanıtları = birebir aynı rota. Rastgelelik böylece ölçülemeyen bir gürültü
/// değil, tekrar oynatılabilen bir girdi olur.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Rota şekli

/// Rotanın kuş uçuşu iskeleti: başlangıç noktası ve etrafında dolaşılan waypoint'ler.
///
/// Waypoint'ler yarıçaptan bağımsız **birim ofsetler** olarak saklanır; gerçek
/// koordinat `başlangıç + r · ofset` ile bulunur. Yani şekil başlangıç noktası
/// etrafında ölçeklenir (homoteti): başlangıç yerinde kalır, kuş uçuşu çevre
/// yarıçapla tam doğru orantılı büyür, P(r) = r · P₁. Yakınsama (`RadiusSolver`)
/// bu özelliğe dayanır: ayarlanacak tek bir sayı kalır, r.
nonisolated struct LoopShape: Equatable {
    /// Yarıçap biriminde doğu/kuzey ofseti.
    struct Offset: Equatable {
        var east: Double
        var north: Double

        static let zero = Offset(east: 0, north: 0)
    }

    /// Başlangıçtan sonraki waypoint'lerin birim ofsetleri, dolaşılma sırasıyla.
    private(set) var offsets: [Offset]
    /// Kullanılamayan waypoint'lerin doğru çekildiği nokta: döngüde elipsin
    /// merkezi, git-gel rotada başlangıcın kendisi.
    let pivot: Offset
    /// Rotanın, başlangıçtan bakınca açıldığı yön (derece).
    let openingBearing: Double

    /// Bacak (= MKDirections isteği) sayısı: her waypoint'e bir bacak + başa dönüş.
    var legCount: Int { offsets.count + 1 }

    /// r = 1 iken kuş uçuşu çevre (P₁).
    var unitPerimeter: Double {
        let ring = [Offset.zero] + offsets + [Offset.zero]
        return zip(ring, ring.dropFirst()).reduce(0) { total, edge in
            total + hypot(edge.1.east - edge.0.east, edge.1.north - edge.0.north)
        }
    }

    /// Döngü şekli. RASTGELE kısım yalnızca burası: köşe sayısı, basıklık,
    /// dönüş yönü ve köşe başına küçük sapma. Açılış yönü dışarıdan gelir;
    /// onun deterministik kısmı `BearingPlanner`'da.
    ///
    /// Köşeler bir elipsin üzerindedir; başlangıç, elipsin açılış yönünün tam
    /// tersindeki ucunda durur. Köşelerin merkez etrafındaki açısı tek yönde
    /// arttığı ve sapma yalnızca merkeze uzaklığı değiştirdiği için çokgen her
    /// zaman yıldız biçimlidir: kuş uçuşu iskelet kendini asla kesmez.
    static func loop(
        openingBearing bearing: Double,
        vertexCountRange: ClosedRange<Int>,
        using random: inout some RandomNumberGenerator
    ) -> LoopShape {
        let vertexCount = Int.random(in: vertexCountRange, using: &random)
        // Enine eksenin boyuna oranı: <1 açılış yönünde uzanan dar döngü,
        // >1 başlangıca yakın kalan geniş döngü.
        let aspect = Double.random(in: 0.65...1.35, using: &random)
        // +1: saat yönünde (önce açılış yönünün soluna gidilir).
        let turn: Double = Bool.random(using: &random) ? 1 : -1

        let offsets = (1..<vertexCount).map { i -> Offset in
            let angle = Double.pi + turn * 2 * .pi * Double(i) / Double(vertexCount)
            let wobble = Double.random(in: 0.88...1.12, using: &random)
            return offset(along: 1 + wobble * cos(angle), across: wobble * aspect * sin(angle), bearing: bearing)
        }

        return LoopShape(
            offsets: offsets,
            pivot: offset(along: 1, across: 0, bearing: bearing),
            openingBearing: bearing
        )
    }

    /// Yedek strateji: tek dönüş noktalı git-gel rota (P₁ = 2).
    static func outAndBack(bearing: Double) -> LoopShape {
        LoopShape(
            offsets: [offset(along: 1, across: 0, bearing: bearing)],
            pivot: .zero,
            openingBearing: bearing
        )
    }

    /// İlk yarıçap tahmini: D ≈ k · r · P₁  ⇒  r₀ = T / (k · P₁).
    func initialRadius(target: Double, detourFactor: Double) -> Double {
        target / (detourFactor * unitPerimeter)
    }

    /// Verilen yarıçapta waypoint koordinatları (başlangıç hariç).
    func waypoints(from start: CLLocationCoordinate2D, radius: Double) -> [CLLocationCoordinate2D] {
        offsets.map { Geo.move(from: start, east: $0.east * radius, north: $0.north * radius) }
    }

    /// Kullanılamayan (su, özel arazi, yolsuz alan) bir waypoint'i pivota doğru
    /// çeker. Açısı değişmediği için yıldız biçim korunur. Şeklin kendisi
    /// değiştiği için sonraki yarıçap turları da düzeltilmiş noktayı kullanır.
    func pullingIn(waypoint index: Int, by factor: Double) -> LoopShape {
        var copy = self
        let point = offsets[index]
        copy.offsets[index] = Offset(
            east: pivot.east + (point.east - pivot.east) * factor,
            north: pivot.north + (point.north - pivot.north) * factor
        )
        return copy
    }

    /// Düzeltme turunda yeni waypoint, bir önceki turdakine `tolerance` metreden
    /// yakınsa eskisi aynen kullanılır.
    ///
    /// MapKit her waypoint'i zaten en yakın yürünebilir yola oturtur; yarım sokak
    /// boyu kaydırmak çoğu zaman aynı bacağı döndürür. Eski koordinatı korumak,
    /// o waypoint'e giren/çıkan bacakları cache'te birebir eşleştirir (istek yok)
    /// ve bacaklar arasında boşluk bırakmaz. Mesafe hep gerçekten kullanılan
    /// bacaklardan ölçüldüğü için doğruluk kaybı olmaz; yakınsama bir sonraki
    /// ölçümle kendini düzeltir.
    static func pin(
        _ proposed: [CLLocationCoordinate2D],
        to previous: [CLLocationCoordinate2D]?,
        tolerance: Double
    ) -> [CLLocationCoordinate2D] {
        guard let previous, previous.count == proposed.count else { return proposed }
        return zip(proposed, previous).map { new, old in
            Geo.distance(new, old) <= tolerance ? old : new
        }
    }

    /// Açılış yönüne göre (boyuna, enine) ofseti doğu/kuzeye çevirir.
    /// Enine pozitif = açılış yönünün sağı.
    private static func offset(along: Double, across: Double, bearing: Double) -> Offset {
        let radians = bearing * .pi / 180
        return Offset(
            east: along * sin(radians) + across * cos(radians),
            north: along * cos(radians) - across * sin(radians)
        )
    }
}

// MARK: - Yakınsama

/// Tek bir şekil için yarıçapı hedef mesafeye yakınsatır. Ağ görmez: ölçülen
/// mesafeyi `record` ile alır, sıradaki denenecek yarıçapı `nextRadius` ile verir.
///
/// **Neden orantısal düzeltme?** Şekil başlangıç etrafında ölçeklendiği için kuş
/// uçuşu çevre P(r) = r · P₁ tam doğrusaldır. Gerçek yol mesafesi D(r) = k(r) · r · P₁;
/// k sokak ağının dolambaç katsayısıdır ve yarıçapla yavaş değişir.
/// r' = r · T / D(r) adımı, k sabitken kökü TEK adımda bulur. k sabit değilse bu
/// bir sabit-nokta iterasyonudur ve bağıl hata her adımda yaklaşık |ε| ile çarpılır;
/// ε = d(ln k) / d(ln r), yani dolambaç katsayısının yarıçapa esnekliği. Pratikte
/// |ε| ≪ 1 olduğundan 1–2 düzeltme ±%10'a iner. İkili arama ise hatayı adım başına
/// yalnızca yarıya indirir ve önce alt/üst sınırı bulmak için ekstra tur (her tur
/// = bacak sayısı kadar istek) harcar.
///
/// **Koruma:** Sokak ağı süreksizdir; bir waypoint başka sokağa atlayınca D sıçrar.
/// Hedefin iki yanında birer ölçüm varsa (bracket) ve orantısal adım bu aralığın
/// dışına düşerse aralığın ortası denenir; aralık her adımda en az yarıya iner.
/// Tur sayısı da `maxEvaluations` ile sınırlı. Aynı ölçümler → aynı yarıçap dizisi.
nonisolated struct RadiusSolver {
    struct Sample: Equatable {
        let radius: Double
        let distance: Double
    }

    /// Tek adımda yarıçap en fazla bu oranda büyür/küçülür: tek bir aykırı ölçüm
    /// (ör. nehir yüzünden dolanan bir bacak) şekli uçurmasın.
    static let maxStepRatio = 2.0

    let target: Double
    let tolerance: Double
    let maxEvaluations: Int
    private let initialRadius: Double
    private(set) var samples: [Sample] = []

    init(target: Double, initialRadius: Double, tolerance: Double, maxEvaluations: Int) {
        self.target = target
        self.initialRadius = initialRadius
        self.tolerance = tolerance
        self.maxEvaluations = maxEvaluations
    }

    /// Hedefe en yakın ölçüm.
    var best: Sample? {
        samples.min { abs($0.distance - target) < abs($1.distance - target) }
    }

    var isConverged: Bool {
        best.map { abs(relativeError(of: $0)) <= tolerance } ?? false
    }

    /// Denenecek sıradaki yarıçap; hedef tuttuysa ya da tur hakkı bittiyse `nil`.
    var nextRadius: Double? {
        guard !isConverged, samples.count < maxEvaluations else { return nil }
        guard let last = samples.last else { return initialRadius }

        let ratio = min(max(target / max(last.distance, 1), 1 / Self.maxStepRatio), Self.maxStepRatio)
        let proportional = last.radius * ratio

        guard let bracket else { return proportional }
        let lower = min(bracket.below.radius, bracket.above.radius)
        let upper = max(bracket.below.radius, bracket.above.radius)
        return (lower < proportional && proportional < upper) ? proportional : (lower + upper) / 2
    }

    func relativeError(of sample: Sample) -> Double {
        (sample.distance - target) / target
    }

    mutating func record(radius: Double, distance: Double) {
        samples.append(Sample(radius: radius, distance: distance))
    }

    /// Hedefin altında ve üstünde kalan, hedefe en yakın iki ölçüm.
    private var bracket: (below: Sample, above: Sample)? {
        let below = samples.filter { $0.distance < target }.max { $0.distance < $1.distance }
        let above = samples.filter { $0.distance > target }.min { $0.distance < $1.distance }
        guard let below, let above else { return nil }
        return (below, above)
    }
}

// MARK: - Yön planı

/// Rotanın hangi yöne açılacağını seçer.
/// - DETERMİNİSTİK: Aynı başlangıçtan önceki rotalar varsa temel yön, hepsine en
///   uzak yöndür. Ardışık denemeler temel yöne altın açı (≈137.5°) eklenerek
///   dağıtılır: n deneme çemberi olabildiğince düzgün tarar, iki deneme aynı yöne
///   düşmez. Bir yönde deniz/otoyol varsa sıradaki deneme bambaşka bir yöne bakar.
/// - RASTGELE: Geçmiş yoksa temel yön; her denemeye eklenen küçük sapma (jitter).
nonisolated enum BearingPlanner {
    static let goldenAngle = 137.507_764

    /// Kullanılmış yönlerin en yakınına en uzak yön (1° çözünürlük); geçmiş yoksa `nil`.
    static func leastUsedBearing(avoiding used: [Double]) -> Double? {
        guard !used.isEmpty else { return nil }
        return stride(from: 0.0, to: 360.0, by: 1.0).max { a, b in
            clearance(of: a, from: used) < clearance(of: b, from: used)
        }
    }

    static func bearing(forAttempt attempt: Int, base: Double, jitter: Double) -> Double {
        let bearing = (base + Double(attempt) * goldenAngle + jitter).truncatingRemainder(dividingBy: 360)
        return bearing < 0 ? bearing + 360 : bearing
    }

    private static func clearance(of bearing: Double, from used: [Double]) -> Double {
        used.map { Geo.angularDifference(bearing, $0) }.min() ?? 180
    }
}

// MARK: - Öğrenilen dolambaç katsayısı

/// Bölgedeki sokak ağının dolambaç katsayısı (yol mesafesi / kuş uçuşu).
///
/// Dünya ~3 km'lik gözlere bölünür; her göz kendi katsayısını öğrenir. İlk rotada
/// varsayılanla başlanır, her ölçümle güncellenir. Sonraki rotaların ilk yarıçap
/// tahmini böylece hedefe çok yakın düşer; düzeltme turu, yani ağ isteği azalır.
/// Öğrenilenler `learnedFactors` ile dışarı verilip oturumlar arasında saklanır
/// (bkz. `DetourStoring`): bilinen bölgede uygulama yeniden açıldığında bile çoğu
/// üretim tek turda biter. Kullanıcının koştuğu bölge sayısı küçük olduğu için
/// sözlük büyümez; sınır gerekmez.
nonisolated struct DetourEstimate {
    /// Şehir içi yürüme ağlarında yol/kuş uçuşu oranı tipik olarak 1.2–1.4 arasıdır.
    static let initial = 1.3
    /// Yeni ölçümün ağırlığı: tek bir aykırı ölçüm tahmini ele geçirmez,
    /// ama 2–3 ölçümde bölgeye uyum sağlanır.
    static let smoothing = 0.5
    /// Göz kenarı (derece; enlemde ~3.3 km). Bir bölgenin sokak dokusu bu
    /// ölçekte kabaca aynıdır.
    static let cellDegrees = 0.03

    /// Göz anahtarı → öğrenilen katsayı. Anahtar `String` tutulur ki sözlük
    /// dönüştürülmeden plist/UserDefaults'a yazılabilsin.
    private(set) var learnedFactors: [String: Double]

    init(learnedFactors: [String: Double] = [:]) {
        self.learnedFactors = learnedFactors
    }

    func factor(near start: CLLocationCoordinate2D) -> Double {
        learnedFactors[Self.cellKey(of: start)] ?? Self.initial
    }

    mutating func observe(_ ratio: Double, at start: CLLocationCoordinate2D) {
        let measured = min(max(ratio, 1.0), 2.5)
        let key = Self.cellKey(of: start)
        if let value = learnedFactors[key] {
            learnedFactors[key] = value + Self.smoothing * (measured - value)
        } else {
            learnedFactors[key] = measured
        }
    }

    private static func cellKey(of coordinate: CLLocationCoordinate2D) -> String {
        let x = Int((coordinate.longitude / Self.cellDegrees).rounded())
        let y = Int((coordinate.latitude / Self.cellDegrees).rounded())
        return "\(x),\(y)"
    }
}

// MARK: - Rota izi

/// Rotayı eşit aralıklı örneklere böler ve bir ızgaraya dizer; "şu nokta rotaya
/// X metreden yakın mı?" sorusunu sabit sürede cevaplar. İki iş için kullanılır:
/// ardışık rotaların örtüşmesi (çeşitlilik) ve rotanın aynı sokağı gidip gelerek
/// iki kez kullanması (çıkmaz sokak "sapı").
nonisolated struct RouteFootprint {
    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    /// Örnekleme aralığı (metre).
    static let spacing = 10.0
    /// Izgara gözü (metre). Sorgu yarıçapı bundan büyük olamaz; 3×3 komşuluk
    /// taraması ancak o zaman eksiksizdir.
    static let cellSize = 30.0

    let samples: [CLLocationCoordinate2D]
    /// Izgaranın sıfır noktası. Her iz kendi yerel ızgarasını kullanır; sorgu
    /// her zaman sorgulanan izin ızgarasında yapıldığı için hizalama gerekmez.
    private let origin: CLLocationCoordinate2D
    private let grid: [Cell: [Int]]

    init(_ coordinates: [CLLocationCoordinate2D]) {
        let samples = Self.resample(coordinates, every: Self.spacing)
        let origin = samples.first ?? CLLocationCoordinate2D()

        var grid: [Cell: [Int]] = [:]
        for (index, sample) in samples.enumerated() {
            grid[Self.cell(of: sample, origin: origin), default: []].append(index)
        }
        self.samples = samples
        self.origin = origin
        self.grid = grid
    }

    /// Bu rotanın, `other`a `corridor` metreden yakın geçen kısmının oranı (0…1).
    ///
    /// Başlangıç çevresi (`startZone`) hesaba katılmaz: aynı yerden çıkan her döngü
    /// ilk ve son birkaç yüz metreyi zorunlu olarak paylaşır (kendi sokağın, tek
    /// köprü, site çıkışı). Bunu benzerlik saymak meşru rotaları da eler.
    func overlap(
        with other: RouteFootprint,
        corridor: Double,
        excluding start: CLLocationCoordinate2D,
        startZone: Double
    ) -> Double {
        let counted = samples.filter { Geo.distance($0, start) > startZone }
        guard !counted.isEmpty else { return 0 }
        let shared = counted.filter { other.hasSample(near: $0, within: corridor) }.count
        return Double(shared) / Double(counted.count)
    }

    /// Rotanın aynı yolu iki kez kullandığı en uzun kesintisiz bölüm (metre).
    ///
    /// Rota boyunca birbirinden en az `minSeparation` uzak iki örnek `sameRoad`
    /// metreden yakınsa o yol iki kez yürünüyor demektir. Döngü başa kapandığı
    /// için uzaklık iki yönden ölçülür; kapanış noktası tekrar sayılmaz.
    func longestRepeatedStretch(
        sameRoad: Double = 15,
        minSeparation: Double = 120,
        excluding start: CLLocationCoordinate2D,
        startZone: Double
    ) -> Double {
        let count = samples.count
        let minGap = Int(minSeparation / Self.spacing)
        guard count > 2 * minGap else { return 0 }

        var longest = 0
        var current = 0
        for (i, sample) in samples.enumerated() {
            let repeated = Geo.distance(sample, start) > startZone && neighbors(of: sample).contains { j in
                let gap = abs(i - j)
                return min(gap, count - gap) >= minGap && Geo.distance(sample, samples[j]) < sameRoad
            }
            current = repeated ? current + 1 : 0
            longest = max(longest, current)
        }
        return Double(longest) * Self.spacing
    }

    private func hasSample(near point: CLLocationCoordinate2D, within radius: Double) -> Bool {
        neighbors(of: point).contains { Geo.distance(point, samples[$0]) <= radius }
    }

    /// Noktanın gözündeki ve 8 komşu gözdeki örneklerin sıraları.
    private func neighbors(of point: CLLocationCoordinate2D) -> [Int] {
        let center = Self.cell(of: point, origin: origin)
        var result: [Int] = []
        for dx in -1...1 {
            for dy in -1...1 {
                result += grid[Cell(x: center.x + dx, y: center.y + dy)] ?? []
            }
        }
        return result
    }

    private static func cell(of coordinate: CLLocationCoordinate2D, origin: CLLocationCoordinate2D) -> Cell {
        let offset = Geo.offset(from: origin, to: coordinate)
        return Cell(
            x: Int((offset.east / cellSize).rounded(.down)),
            y: Int((offset.north / cellSize).rounded(.down))
        )
    }

    /// Koordinatları eşit aralıklı örneklere çevirir: uzun düz parçalara ara
    /// noktalar eklenir, sık noktalar seyreltilir.
    private static func resample(_ coordinates: [CLLocationCoordinate2D], every step: Double) -> [CLLocationCoordinate2D] {
        guard let first = coordinates.first else { return [] }

        var samples = [first]
        var sinceLastSample = 0.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let length = Geo.distance(a, b)
            guard length > 0 else { continue }

            var position = step - sinceLastSample
            while position <= length {
                samples.append(Geo.interpolate(from: a, to: b, fraction: position / length))
                position += step
            }
            sinceLastSample = length - (position - step)
        }
        return samples
    }
}
