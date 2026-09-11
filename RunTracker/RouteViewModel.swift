//
//  RouteViewModel.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 31.08.2026.
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Üretilen rota

/// Kullanıcıya gösterilen tek bir döngü rotası.
struct GeneratedRoute: Identifiable {
    let id = UUID()
    /// Rotanın başladığı ve bittiği nokta.
    let start: CLLocationCoordinate2D
    /// Sırayla çizilince döngüyü oluşturan yürüyüş parçaları.
    let legs: [MKRoute]
    /// Rotanın toplam uzunluğu (metre).
    let distance: Double
    /// Döngünün merkezi — rotanın hangi yöne açıldığını anlamak için.
    let center: CLLocationCoordinate2D

    var polylines: [MKPolyline] { legs.map(\.polyline) }
    var distanceInKm: Double { distance / 1000 }
    /// Rotanın gidiş yönünü gösteren oklar.
    var directionArrows: [RouteArrow] { RouteArrow.along(polylines) }
}

enum RouteGenerationError: Error {
    /// Yeni rota üretilemedi ve gösterilebilecek eski bir rota da yok.
    case noRouteFound
}

// MARK: - Rota üretici

/// Kullanıcının konumundan başlayıp aynı noktada biten, elips biçiminde rastgele
/// koşu döngüleri üretir. Ürettiği rotaları saklar; yeni rota bulunamazsa
/// eskileri sırayla tekrar gösterir.
@MainActor
@Observable
final class RouteGenerator {

    // MARK: Ayarlar

    /// Döngüdeki köşe sayısı aralığı (başlangıç noktası dahil). Her denemede
    /// buradan rastgele seçilir; köşe sayısı değiştikçe döngünün karakteri de
    /// değişir, bu da aynı yerden farklı rotalar çıkmasını kolaylaştırır.
    var vertexCountRange = 5...7
    /// Yeni bir rota için kaç farklı elips denenecek. Parçalar paralel çekildiği
    /// için bir deneme ucuzdur; elenen şekillerin yerine yenisini denemek kolaydır.
    var maxAttempts = 12
    /// Hedef mesafeye yaklaşmak için yarıçapın kaç kez düzeltileceği.
    var maxRefinements = 3
    /// Yarıçap düzeltmesini durduran sapma (0.12 = ±%12).
    var distanceTolerance = 0.12
    /// Kullanıcıya gösterilebilecek en büyük sapma (0.20 = ±%20).
    var maxDistanceError = 0.20
    /// Üretim için ayrılan üst süre. MapKit istekleri sınırladığında denemeler
    /// uzayabilir; kullanıcıyı bekletmemek için süre dolunca geçmişe düşülür.
    var timeLimit: Duration = .seconds(15)
    /// Bir çağrıda yapılabilecek en fazla MKDirections isteği. Apple istekleri
    /// sunucu tarafında sınırlar, ama tek bir denemenin kendisi bir turda
    /// köşe sayısı kadar istek harcar: bütçe birkaç denemeye yetmezse üretim
    /// daha ilk elenen şekilde durur ve hep aynı rotalar gösterilir.
    var requestBudget = 60

    /// İlk kaç deneme, geçmişte kullanılmamış bir yöne açılan şekillerle yapılır.
    /// Kalan denemelerde yön kısıtı kalkar; kısıtlı yönde rota bulunamayan
    /// yerlerde (deniz kıyısı, şehir sınırı) üretim tıkanmasın.
    private let directedAttempts = 6

    /// MapKit, erişilemeyen bir waypoint'i en yakın yola bağlar. Bu mesafe aşılırsa
    /// nokta gerçekten kullanılabilir değildir (su, özel arazi, yolsuz alan).
    private let maxSnapDistance = 200.0
    /// Aynı yolun iki kez kullanılmasına izin verilen en uzun bölüm (metre).
    /// Kavşaklarda kısa örtüşmeler normaldir; bir sokağa girip geri dönmek değildir.
    private let maxRepeatedStretch = 60.0
    /// Bu mesafeden yakın başlangıçlar "aynı yer" sayılır.
    private let sameStartDistance = 150.0
    /// İki rotanın "aynı rota" sayılması için gereken örtüşme oranı.
    private let sameRouteOverlap = 0.55
    /// Örtüşme ölçümünün ızgara çözünürlüğü (metre).
    private let footprintCellSize = 35.0

    /// Bir waypoint kullanılabilir değilse sırayla denenecek düzeltmeler:
    /// önce hafif döndürme, sonra merkeze doğru çekme (kıyı, park kenarı, çıkmaz sokak).
    /// İkisi de waypoint'in merkez etrafındaki açı sırasını bozmaz — yarıçapı değiştirmek
    /// açıyı değiştirmediği için döngünün kendi üzerine binmeme garantisi korunur.
    private let waypointAdjustments: [(rotation: Double, scale: Double)] = [
        (0, 1.00), (12, 1.00), (-12, 1.00),
        (0, 0.72), (20, 0.80), (-20, 0.80),
        (0, 0.45), (20, 0.55), (-20, 0.55)
    ]

    // MARK: Geçmiş

    /// Geçmişte tutulan bir rota ve onu karşılaştırmak için gereken bilgiler.
    private struct Remembered {
        let route: GeneratedRoute
        /// Rotanın harita üzerinde kapladığı ızgara gözleri, komşularıyla
        /// birlikte genişletilmiş: aynı sokağın iki yanına düşen örnekler de
        /// örtüşmüş sayılır.
        let cells: Set<GridCell>
        /// Döngünün, başlangıç noktasından bakınca hangi yöne açıldığı (derece).
        let bearing: Double
    }

    private var entries: [Remembered] = []

    /// Bu oturumda üretilmiş rotalar.
    var history: [GeneratedRoute] { entries.map(\.route) }
    /// Son çağrıda yeni rota üretilemeyip geçmişten bir rota gösterildiyse `true`.
    private(set) var isShowingCachedRoute = false

    private var cycleIndex = 0
    private let historyLimit = 12

    private var deadline = ContinuousClock.now
    /// Bu çağrıda yapılmış MKDirections isteği sayısı.
    private var requestCount = 0
    /// Sunucu istekleri sınırlamaya başladı; ısrar etmek sınırlamayı uzatır.
    private var wasThrottled = false

    /// Üretimi durduran koşulların tümü: süre doldu, istek bütçesi bitti ya da
    /// sunucu istekleri sınırlıyor. Üretimin her adımında kontrol edilir;
    /// tek bir deneme takılırsa diğerlerini beklemeden geçmişe düşülür.
    private var shouldStop: Bool {
        ContinuousClock.now >= deadline || wasThrottled || requestCount >= requestBudget
    }

    /// Daha önce çekilmiş parçalar. Onarım ve iyileştirme turlarında yalnızca
    /// değişen waypoint'lerin parçaları yeniden istenir; kalanlar buradan döner.
    private var legCache: [String: MKRoute] = [:]
    private let legCacheLimit = 200

    // MARK: Genel kullanım

    /// Başlangıç noktasına geri dönen rastgele bir döngü üretir.
    /// Her çağrı farklı bir rota döner; üretim limiti dolarsa daha önce
    /// üretilmiş rotalar sırayla gösterilir.
    func generateLoop(
        from start: CLLocationCoordinate2D,
        targetDistanceMeters target: Double
    ) async throws -> GeneratedRoute {

        deadline = .now + timeLimit
        requestCount = 0
        wasThrottled = false

        // Aynı yerden üretilmiş rotaların yönleri; yeni rota öncelikle
        // bunlardan en uzak yöne açılan şekillerle aranır.
        let unusedBearing = preferredBearing(near: start)

        for attempt in 0..<maxAttempts where !shouldStop {
            let shape = LoopShape.random(
                vertexCount: Int.random(in: vertexCountRange),
                towards: attempt < directedAttempts ? unusedBearing : nil
            )

            guard let candidate = await bestFit(of: shape, from: start, target: target),
                  isUsable(candidate, target: target) else { continue }

            remember(candidate)
            isShowingCachedRoute = false
            return candidate
        }

        return try cachedRoute(near: start)
    }

    /// Geçmişi temizler; kullanıcı başka bir şehre/konuma geçtiğinde çağrılabilir.
    func reset() {
        entries.removeAll()
        legCache.removeAll()
        cycleIndex = 0
        isShowingCachedRoute = false
    }

    // MARK: Rota kurma

    /// Elipsin şeklini koruyarak yarıçapını büyütüp küçültür ve hedefe en yakın döngüyü döner.
    private func bestFit(
        of shape: LoopShape,
        from start: CLLocationCoordinate2D,
        target: Double
    ) async -> GeneratedRoute? {

        var radius = shape.initialRadius(for: target)
        var best: GeneratedRoute?

        for _ in 0..<maxRefinements where !shouldStop {
            let center = shape.center(startingAt: start, radius: radius)
            let waypoints = shape.waypoints(around: center, radius: radius)

            guard let loop = await walk(from: start, through: waypoints, around: center) else { break }

            if best == nil || abs(loop.distance - target) < abs(best!.distance - target) {
                best = loop
            }
            if abs(loop.distance - target) / target <= distanceTolerance { break }

            // Rota uzunluğu yarıçapla neredeyse doğru orantılı; oranı doğrudan
            // uygulamak ikili aramadan çok daha hızlı yakınsar.
            radius *= min(max(target / loop.distance, 0.6), 1.7)
        }
        return best
    }

    /// Döngünün bütün parçalarını aynı anda çeker. Kullanılamayan bir waypoint
    /// çıkarsa onu `waypointAdjustments` ile düzeltip turu tekrarlar.
    private func walk(
        from start: CLLocationCoordinate2D,
        through waypoints: [CLLocationCoordinate2D],
        around center: CLLocationCoordinate2D
    ) async -> GeneratedRoute? {

        // path[0] başlangıç, path[k] ise waypoints[k - 1]; son parça başa döner.
        var path = [start] + waypoints
        var adjustmentStep = [Int](repeating: 0, count: path.count)

        for _ in waypointAdjustments.indices {
            guard !shouldStop else { return nil }
            let legs = await fetchLegs(along: path)

            // legs[i] parçası path[i + 1] hedefine gider; boşsa o hedef kullanılamıyor.
            let unusable = legs.indices.filter { legs[$0] == nil }.map { ($0 + 1) % path.count }
            if unusable.isEmpty {
                let found = legs.compactMap { $0 }
                return GeneratedRoute(
                    start: start,
                    legs: found,
                    distance: found.reduce(0) { $0 + $1.distance },
                    center: center
                )
            }

            // Başlangıç noktası kullanıcının konumu; oraya dönülemiyorsa bu şekil işe yaramaz.
            guard !unusable.contains(0) else { return nil }

            for target in unusable {
                adjustmentStep[target] += 1
                guard adjustmentStep[target] < waypointAdjustments.count else { return nil }

                let adjustment = waypointAdjustments[adjustmentStep[target]]
                path[target] = Geo.adjust(
                    waypoints[target - 1], around: center,
                    rotateBy: adjustment.rotation, scaleBy: adjustment.scale
                )
            }
        }
        return nil
    }

    /// Ardışık noktalar arasındaki parçaları paralel çeker — sıralı çekmeye göre
    /// bekleme süresi parça sayısı kadar kısalır. Sonuçlar sıralarında kalır.
    private func fetchLegs(along path: [CLLocationCoordinate2D]) async -> [MKRoute?] {
        await withTaskGroup(of: (index: Int, leg: MKRoute?).self) { group in
            for i in path.indices {
                group.addTask { [self] in
                    (i, await usableLeg(from: path[i], to: path[(i + 1) % path.count]))
                }
            }

            var legs = [MKRoute?](repeating: nil, count: path.count)
            for await result in group { legs[result.index] = result.leg }
            return legs
        }
    }

    /// Parçayı çeker ve hedefin gerçekten kullanılabilir olduğunu doğrular: MapKit
    /// noktayı çok uzaktaki bir yola bağladıysa orası yürünebilir değil demektir.
    /// Aynı parça daha önce çekildiyse istek yapılmadan önbellekten döner.
    private func usableLeg(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> MKRoute? {
        let key = legKey(from, to)
        if let cached = legCache[key] { return cached }

        guard let leg = await walkingLeg(from: from, to: to),
              let end = Geo.lastCoordinate(of: leg.polyline),
              Geo.distance(end, to) <= maxSnapDistance else { return nil }

        if legCache.count >= legCacheLimit { legCache.removeAll() }
        legCache[key] = leg
        return leg
    }

    /// Önbellek anahtarı: ~1 m çözünürlüğe yuvarlanmış koordinat çifti.
    private func legKey(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f-%.5f,%.5f", from.latitude, from.longitude, to.latitude, to.longitude)
    }

    /// İki nokta arasındaki gerçek yürüme rotasını MapKit'ten çeker.
    private func walkingLeg(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> MKRoute? {

        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .walking

        for attempt in 0..<2 {
            guard !shouldStop else { return nil }
            requestCount += 1
            do {
                return try await MKDirections(request: request).calculate().routes.first
            } catch let error as MKError where error.code == .loadingThrottled {
                // Sunucu istekleri sınırlamaya başladı. Bir kez kısa bekleyip
                // tekrar dene; yine olmazsa üretimin tamamını durdur — ısrar
                // etmek hem süreyi tüketir hem sınırlamayı derinleştirir.
                if attempt == 0 {
                    try? await Task.sleep(for: .seconds(0.5))
                } else {
                    wasThrottled = true
                }
            } catch let error as MKError where isTemporary(error) {
                // Anlık bir sunucu sorunu; waypoint'i suçlamadan bir kez daha dene.
                try? await Task.sleep(for: .seconds(0.5))
            } catch {
                return nil // bu noktaya yürünebilir bir yol yok
            }
        }
        return nil
    }

    /// Tekrar denemeye değer geçici hata mı? `directionsNotFound` gibi kalıcı
    /// hatalar nokta kullanılamaz demektir; `loadingThrottled` ise burada değil,
    /// tüm üretimi durduran ayrı bir sinyal olarak ele alınır.
    private func isTemporary(_ error: MKError) -> Bool {
        [.serverFailure, .unknown].contains(error.code)
    }

    // MARK: Doğrulama

    /// Rota hedefe yeterince yakın mı, kendi üzerine binmiyor mu, daha önce gösterilmemiş mi?
    private func isUsable(_ route: GeneratedRoute, target: Double) -> Bool {
        abs(route.distance - target) / target <= maxDistanceError
            && repeatedStretch(of: route) <= maxRepeatedStretch
            && !isTooSimilar(route)
    }

    /// Rotanın aynı yolu iki kez kullandığı en uzun kesintisiz bölüm (metre).
    /// Bir sokağa girip aynı sokaktan geri dönen kısa "çıkmaz" parçaları
    /// toplam orana bakan bir ölçüm kaçırır; en uzun parçaya bakmak onları yakalar.
    private func repeatedStretch(of route: GeneratedRoute) -> Double {
        let spacing = 20.0          // örnekleme aralığı (metre)
        let minSeparation = 3       // ~60 m: bundan yakın örnekler zaten komşudur
        let sameRoadDistance = 15.0 // bu kadar yakınsa aynı yoldan geçiyor sayılır

        let samples = resample(route.polylines.flatMap(Geo.coordinates), everyMeters: spacing)
        guard samples.count > 2 * minSeparation else { return 0 }

        var longestRun = 0
        var currentRun = 0

        for i in samples.indices {
            let travelledTwice = samples.indices.contains { j in
                // Döngü başa döndüğü için uzaklık iki yönden de ölçülmeli;
                // böylece rotanın kapandığı yer "tekrar" sayılmaz.
                let gap = abs(i - j)
                let loopGap = min(gap, samples.count - gap)
                return loopGap >= minSeparation
                    && Geo.distance(samples[i], samples[j]) < sameRoadDistance
            }

            currentRun = travelledTwice ? currentRun + 1 : 0
            longestRun = max(longestRun, currentRun)
        }
        return Double(longestRun) * spacing
    }

    /// Noktaları yaklaşık eşit aralıklarla seyreltir; örtüşme kontrolünü ucuzlatır.
    private func resample(_ coordinates: [CLLocationCoordinate2D], everyMeters step: Double) -> [CLLocationCoordinate2D] {
        guard let first = coordinates.first else { return [] }

        var samples = [first]
        var travelled = 0.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            travelled += Geo.distance(a, b)
            if travelled >= step {
                samples.append(b)
                travelled = 0
            }
        }
        return samples
    }

    // MARK: Geçmiş yönetimi

    /// Rota, daha önce gösterilmiş bir rotayla büyük ölçüde aynı sokaklardan mı geçiyor?
    ///
    /// Merkez ve uzunluk karşılaştırmak burada işe yaramaz: aynı noktadan
    /// başlayıp aynı hedef mesafeyi tutturan her döngünün merkezi de uzunluğu da
    /// birbirine yakın çıkar, dolayısıyla ilk bir iki rotadan sonra her yeni
    /// aday "aynı" sayılıp elenir. Onun yerine rotaların haritada gerçekten
    /// kapladığı gözler karşılaştırılır: farklı sokaklardan geçen iki döngü,
    /// merkezleri çakışsa bile ayrı rotalardır.
    private func isTooSimilar(_ route: GeneratedRoute) -> Bool {
        let cells = GridCell.footprint(of: route.polylines, size: footprintCellSize)
        guard !cells.isEmpty else { return false }

        return entries.contains { existing in
            let shared = cells.filter(existing.cells.contains).count
            return Double(shared) / Double(cells.count) >= sameRouteOverlap
        }
    }

    /// Yakında üretilmiş rotaların yönlerinden en uzak yön. Aynı yerden art arda
    /// üretilen rotalar böylece farklı yönlere açılır.
    private func preferredBearing(near start: CLLocationCoordinate2D) -> Double? {
        let used = entries
            .filter { Geo.distance($0.route.start, start) < sameStartDistance }
            .map(\.bearing)
        guard !used.isEmpty else { return nil }

        // Tüm yönler 15 derece adımlarla taranır; kullanılanlara en uzak olan seçilir.
        return stride(from: 0.0, to: 360.0, by: 15.0).max { a, b in
            clearance(of: a, from: used) < clearance(of: b, from: used)
        }
    }

    /// Bir yönün, daha önce kullanılmış yönlerin en yakınına olan açı farkı.
    private func clearance(of bearing: Double, from used: [Double]) -> Double {
        used.map { Geo.angularDifference(bearing, $0) }.min() ?? 180
    }

    private func remember(_ route: GeneratedRoute) {
        entries.append(Remembered(
            route: route,
            cells: GridCell.footprint(of: route.polylines, size: footprintCellSize).expanded(),
            bearing: Geo.bearing(from: route.start, to: route.center)
        ))
        if entries.count > historyLimit { entries.removeFirst() }
    }

    /// Yeni rota üretilemedi: aynı yerden başlayan eski rotaları sırayla göster.
    /// Kullanıcı başka bir yere gittiyse oradaki rotalar burada işe yaramaz.
    private func cachedRoute(near start: CLLocationCoordinate2D) throws -> GeneratedRoute {
        let nearby = entries.map(\.route).filter { Geo.distance($0.start, start) < sameStartDistance }
        guard !nearby.isEmpty else { throw RouteGenerationError.noRouteFound }

        let route = nearby[cycleIndex % nearby.count]
        cycleIndex += 1
        isShowingCachedRoute = true
        return route
    }
}

// MARK: - Rota izi

/// Kaba bir harita ızgarasının tek bir gözü. İki rotanın aynı sokaklardan geçip
/// geçmediği, kapladıkları göz kümelerinin örtüşmesiyle ölçülür.
private struct GridCell: Hashable {
    let x: Int
    let y: Int

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    init(_ coordinate: CLLocationCoordinate2D, size: Double) {
        let metersPerLatitudeDegree = Geo.earthRadius * .pi / 180
        let metersPerLongitudeDegree = metersPerLatitudeDegree * cos(coordinate.latitude * .pi / 180)
        x = Int((coordinate.longitude * metersPerLongitudeDegree / size).rounded(.down))
        y = Int((coordinate.latitude * metersPerLatitudeDegree / size).rounded(.down))
    }

    /// Rotanın geçtiği gözler. Çizgi, göz boyunun yarısı aralıklarla örneklenir;
    /// uzun düz parçalarda aradaki gözler atlanmasın.
    static func footprint(of polylines: [MKPolyline], size: Double) -> Set<GridCell> {
        let path = Geo.joinedCoordinates(of: polylines)
        guard let first = path.first else { return [] }

        var cells: Set<GridCell> = [GridCell(first, size: size)]
        for (a, b) in zip(path, path.dropFirst()) {
            let steps = max(Int(Geo.distance(a, b) / (size / 2)), 1)
            for i in 1...steps {
                let point = Geo.interpolate(from: a, to: b, fraction: Double(i) / Double(steps))
                cells.insert(GridCell(point, size: size))
            }
        }
        return cells
    }
}

private extension Set where Element == GridCell {
    /// Kümeyi komşu gözlerle genişletir: aynı sokaktan geçen iki rota, örnekleri
    /// ızgaranın iki yanına düşse bile örtüşmüş sayılır.
    func expanded() -> Set<GridCell> {
        var expanded = Set<GridCell>(minimumCapacity: count * 9)
        for cell in self {
            for dx in -1...1 {
                for dy in -1...1 {
                    expanded.insert(GridCell(x: cell.x + dx, y: cell.y + dy))
                }
            }
        }
        return expanded
    }
}

// MARK: - Döngü şekli

/// Rotanın geometrisi: rastgele yönlendirilmiş, hafifçe basık bir elips.
/// Waypoint'ler elipsin üzerinde tek yönde ilerlediği için köşeler arasında
/// ileri geri gidiş olmaz ve rota kendi üzerine binmez.
private struct LoopShape {
    /// Elipsin kuzeye göre dönüklüğü (radyan).
    let rotation: Double
    /// Kısa eksenin uzuna oranı (1.0 = daire, 0.62 = belirgin elips).
    let flattening: Double
    /// Başlangıç noktasının elips üzerindeki açısı (radyan).
    let startAngle: Double
    /// Dönüş yönü: +1 saat yönünün tersi, -1 saat yönü.
    let direction: Double
    /// Waypoint başına küçük yarıçap sapması — rotanın fazla "geometrik" görünmesini engeller.
    /// Açıyı değiştirmediği için döngünün kendi üzerine binmemesi garantisi korunur.
    let wobble: [Double]

    /// İstenen yöne "yeterince yakın" sayılan sapma (derece).
    private static let sectorWidth = 35.0

    /// Başlangıç noktası dahil köşe sayısı.
    var vertexCount: Int { wobble.count + 1 }

    /// Döngünün, başlangıç noktasından bakınca hangi yöne açıldığı (derece):
    /// merkezin başlangıca göre yönü. Yarıçaptan bağımsızdır.
    var openingBearing: Double {
        let start = offset(atAngle: startAngle, radius: 1)
        let degrees = atan2(-start.east, -start.north) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Her çağrıda farklı bir elips — rotaların rastgeleliği buradan gelir.
    /// `bearing` verilirse o yöne açılan bir şekil aranır; şekil üretmek yalnızca
    /// aritmetik olduğu için denemek ağ isteği maliyeti getirmez.
    static func random(vertexCount: Int, towards bearing: Double?) -> LoopShape {
        var shape = randomShape(vertexCount: vertexCount)
        guard let bearing else { return shape }

        var attempts = 0
        while Geo.angularDifference(shape.openingBearing, bearing) > sectorWidth, attempts < 100 {
            shape = randomShape(vertexCount: vertexCount)
            attempts += 1
        }
        return shape
    }

    private static func randomShape(vertexCount: Int) -> LoopShape {
        LoopShape(
            rotation: .random(in: 0..<(2 * .pi)),
            flattening: .random(in: 0.62...1.0),
            startAngle: .random(in: 0..<(2 * .pi)),
            direction: Bool.random() ? 1 : -1,
            wobble: (0..<max(vertexCount - 1, 2)).map { _ in Double.random(in: 0.85...1.15) }
        )
    }

    /// Hedef mesafe için makul bir başlangıç yarıçapı.
    /// Çevre ≈ n · 2r · sin(π/n); yolların düz gitmemesi için ~%15 pay bırakılır.
    func initialRadius(for target: Double) -> Double {
        let polygonFactor = Double(vertexCount) * 2 * sin(.pi / Double(vertexCount))
        let averageRadiusRatio = (1 + flattening) / 2
        return target / (polygonFactor * averageRadiusRatio * 1.15)
    }

    /// Başlangıç noktası elipsin üzerinde kalacak şekilde merkezi hesaplar,
    /// böylece rota kullanıcının bulunduğu yerde başlar ve orada biter.
    func center(startingAt start: CLLocationCoordinate2D, radius: Double) -> CLLocationCoordinate2D {
        // Merkez, başlangıç noktasının elips üzerindeki konumunun tersi yönünde kalır.
        let startOffset = offset(atAngle: startAngle, radius: radius)
        return Geo.move(from: start, east: -startOffset.east, north: -startOffset.north)
    }

    /// Elips üzerindeki noktanın merkeze göre metre cinsinden konumu.
    private func offset(atAngle angle: Double, radius: Double) -> (east: Double, north: Double) {
        let x = radius * cos(angle)
        let y = radius * flattening * sin(angle)
        return (east: x * cos(rotation) - y * sin(rotation),
                north: x * sin(rotation) + y * cos(rotation))
    }

    /// Başlangıçtan sonraki waypoint'ler. Açı tek yönde arttığı için sıralama korunur.
    func waypoints(around center: CLLocationCoordinate2D, radius: Double) -> [CLLocationCoordinate2D] {
        let step = 2 * Double.pi / Double(vertexCount)

        return wobble.indices.map { i in
            let angle = startAngle + direction * step * Double(i + 1)
            let point = offset(atAngle: angle, radius: radius)
            return Geo.move(from: center, east: point.east * wobble[i], north: point.north * wobble[i])
        }
    }
}
