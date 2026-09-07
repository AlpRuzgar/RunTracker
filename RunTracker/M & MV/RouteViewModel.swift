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
    /// Döngünün merkezi — aynı rotanın tekrar üretilip üretilmediğini anlamak için.
    let center: CLLocationCoordinate2D

    var polylines: [MKPolyline] { legs.map(\.polyline) }
    var distanceInKm: Double { distance / 1000 }
}

enum RouteGenerationError: Error {
    /// Yeni rota üretilemedi ve gösterilebilecek eski bir rota da yok.
    case noRouteFound
}

// MARK: - Rota üretici

/// Kullanıcının konumundan başlayıp aynı noktada biten, elips biçiminde rastgele
/// koşu döngüleri üretir. Ürettiği rotaları saklar; yeni bir rota bulunamazsa
/// eskileri sırayla tekrar gösterir.
@MainActor
@Observable
final class RouteGenerator {

    // MARK: Ayarlar

    /// Döngüdeki köşe sayısı (başlangıç noktası dahil).
    var vertexCount = 6
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
    /// sunucu tarafında sınırlar; tek dokunuşta büyük istek yığınları göndermek
    /// sonraki çağrıların da sınırlanmasına yol açar. Bütçe dolunca geçmişe düşülür.
    var requestBudget = 25

    /// MapKit, erişilemeyen bir waypoint'i en yakın yola bağlar. Bu mesafe aşılırsa
    /// nokta gerçekten kullanılabilir değildir (su, özel arazi, yolsuz alan).
    private let maxSnapDistance = 200.0
    /// Aynı yolun iki kez kullanılmasına izin verilen en uzun bölüm (metre).
    /// Kavşaklarda kısa örtüşmeler normaldir; bir sokağa girip geri dönmek değildir.
    private let maxRepeatedStretch = 60.0
    /// Bu mesafeden yakın başlangıçlar "aynı yer" sayılır.
    private let sameStartDistance = 150.0
    /// Merkezleri ve uzunlukları bu kadar yakın olan iki rota "aynı rota" sayılır.
    private let sameCenterDistance = 120.0
    private let sameLengthDifference = 250.0

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

    /// Bu oturumda üretilmiş rotalar.
    private(set) var history: [GeneratedRoute] = []
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

        for _ in 0..<maxAttempts where !shouldStop {
            let shape = LoopShape.random(vertexCount: vertexCount)

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
        history.removeAll()
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

    /// Aynı sokakların tekrar tekrar önerilmemesi için geçmişle karşılaştırır.
    private func isTooSimilar(_ route: GeneratedRoute) -> Bool {
        history.contains { existing in
            Geo.distance(existing.center, route.center) < sameCenterDistance
                && abs(existing.distance - route.distance) < sameLengthDifference
        }
    }

    private func remember(_ route: GeneratedRoute) {
        history.append(route)
        if history.count > historyLimit { history.removeFirst() }
    }

    /// Yeni rota üretilemedi: aynı yerden başlayan eski rotaları sırayla göster.
    /// Kullanıcı başka bir yere gittiyse oradaki rotalar burada işe yaramaz.
    private func cachedRoute(near start: CLLocationCoordinate2D) throws -> GeneratedRoute {
        let nearby = history.filter { Geo.distance($0.start, start) < sameStartDistance }
        guard !nearby.isEmpty else { throw RouteGenerationError.noRouteFound }

        let route = nearby[cycleIndex % nearby.count]
        cycleIndex += 1
        isShowingCachedRoute = true
        return route
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

    /// Başlangıç noktası dahil köşe sayısı.
    var vertexCount: Int { wobble.count + 1 }

    /// Her çağrıda farklı bir elips — rotaların rastgeleliği buradan gelir.
    static func random(vertexCount: Int) -> LoopShape {
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

// MARK: - Geometri yardımcıları

private enum Geo {
    static let earthRadius = 6_371_000.0

    /// Bir koordinattan verilen yön ve mesafedeki noktayı bulur (great-circle).
    static func destination(
        from coordinate: CLLocationCoordinate2D,
        bearingDegrees: Double,
        distanceMeters: Double
    ) -> CLLocationCoordinate2D {

        let bearing = bearingDegrees * .pi / 180
        let angular = distanceMeters / earthRadius
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// Koordinatı doğu/kuzey yönünde metre cinsinden kaydırır.
    static func move(from coordinate: CLLocationCoordinate2D, east: Double, north: Double) -> CLLocationCoordinate2D {
        let distance = hypot(east, north)
        guard distance > 0 else { return coordinate }
        return destination(from: coordinate, bearingDegrees: atan2(east, north) * 180 / .pi, distanceMeters: distance)
    }

    /// İki koordinat arası mesafe (metre). Kısa mesafelerde düzlemsel yaklaşım hem yeterli hem hızlı.
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let meanLatitude = (a.latitude + b.latitude) / 2 * .pi / 180
        let dx = (b.longitude - a.longitude) * .pi / 180 * cos(meanLatitude)
        let dy = (b.latitude - a.latitude) * .pi / 180
        return hypot(dx, dy) * earthRadius
    }

    /// a noktasından b noktasına bakış yönü (derece).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return atan2(y, x) * 180 / .pi
    }

    /// Noktayı merkez etrafında döndürür ve/veya merkeze doğru çeker.
    static func adjust(
        _ point: CLLocationCoordinate2D,
        around center: CLLocationCoordinate2D,
        rotateBy degrees: Double,
        scaleBy factor: Double
    ) -> CLLocationCoordinate2D {
        guard degrees != 0 || factor != 1 else { return point }
        return destination(
            from: center,
            bearingDegrees: bearing(from: center, to: point) + degrees,
            distanceMeters: distance(center, point) * factor
        )
    }

    static func coordinates(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return coordinates
    }

    static func lastCoordinate(of polyline: MKPolyline) -> CLLocationCoordinate2D? {
        coordinates(of: polyline).last
    }
}
