//
//  NavigationViewModel.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Navigasyon durumu

enum NavigationState {
    /// Navigasyon başlamadı ya da durduruldu.
    case idle
    /// Rota takip ediliyor.
    case navigating
    /// Kullanıcı rotadan çıktı; bağlantı rotası çekiliyor.
    case rerouting
    /// Döngü tamamlandı.
    case finished
}

// MARK: - Navigasyon view model

/// Üretilmiş bir döngü rotası üzerinde adım adım yol tarifi verir: sıradaki
/// manevra talimatını, manevraya ve bitişe kalan mesafeyi günceller. Kullanıcı
/// rotadan uzaklaşırsa MapKit'ten bağlantı rotası çekip rotayı yeniden kurar.
///
/// Konumu kendisi dinlemez; görünüm her yeni konumda `update(location:)`
/// çağırır. Böylece `LocationManager`'a bağımlı olmaz ve test edilebilir kalır.
@MainActor
@Observable
final class NavigationViewModel {

    // MARK: Ayarlar

    /// Rotadan bu kadar uzaklaşmak "rota dışı" sayılır (metre). GPS'in o anki
    /// doğruluğu kötüyse eşik otomatik genişler.
    var offRouteThreshold = 40.0
    /// GPS sıçramalarının hemen yeniden rota çizdirmemesi için art arda bu
    /// kadar güncelleme rota dışı kalınmalıdır.
    var offRouteConfirmationCount = 3
    /// Bitişe bu mesafeden yaklaşınca navigasyon tamamlanmış sayılır (metre).
    var arrivalRadius = 25.0
    /// İki yeniden rota isteği arasındaki en kısa süre. MapKit istekleri
    /// sunucu tarafında sınırlar (bkz. `RouteGenerator`); art arda istek
    /// atmak sonraki istekleri de baltalar.
    var rerouteCooldown: Duration = .seconds(10)
    /// Yeniden rota çizilirken rotaya bu kadar ileriden bağlanılır (metre);
    /// kullanıcıyı kaçırdığı manevraya geri yürütmek yerine akışa devam ettirir.
    var rejoinLookahead = 150.0
    /// Bu doğruluktan kötü konumlar (metre) hiç kullanılmaz: bir sokak
    /// genişliğinden fazla belirsiz bir konum, rotayı yanlış yere oturtur.
    var maxAcceptableAccuracy = 65.0
    /// Konum bu kadar eskiyse yok sayılır (saniye). CoreLocation ilk anda
    /// dakikalar önce alınmış bir fix'i teslim edebilir.
    var maxLocationAge = 8.0

    // MARK: Dışa açık durum

    private(set) var state: NavigationState = .idle
    /// Sıradaki manevranın talimatı (MapKit'ten, yerelleştirilmiş).
    private(set) var currentInstruction = ""
    /// Sıradaki manevraya kalan mesafe (metre).
    private(set) var distanceToNextManeuver = 0.0
    /// Bitişe kalan mesafe (metre).
    private(set) var remainingDistance = 0.0
    /// Haritada çizilecek güncel rota; yeniden rota sonrasında değişir.
    private(set) var polylines: [MKPolyline] = []
    /// Güncel rotanın gidiş yönünü gösteren oklar.
    private(set) var arrows: [RouteArrow] = []
    /// Kullanıcının rotaya olan dik uzaklığı (metre).
    private(set) var offRouteDistance = 0.0
    /// Kullanıcı şu an rotanın dışında mı? (Henüz yeniden rota çizdirecek
    /// kadar uzun sürmemiş olabilir.)
    var isOffRoute: Bool { offRouteCount > 0 }

    /// Rotanın tamamlanan oranı (0...1) — ilerleme göstergeleri için.
    var progressFraction: Double {
        totalDistance > 0 ? min(max(progressTravelled / totalDistance, 0), 1) : 0
    }

    // MARK: İç durum

    /// Talimatıyla birlikte tek bir manevra parçası.
    private struct Step {
        let instruction: String
        let polyline: MKPolyline
    }

    /// Rota çizgisinin bir köşesi.
    private struct RoutePoint {
        let coordinate: CLLocationCoordinate2D
        /// Bu noktanın ait olduğu adımın `steps` içindeki sırası.
        let stepIndex: Int
        /// Rota başından bu noktaya yürünen mesafe (metre).
        let travelled: Double
    }

    /// Bir konumun rota üzerine oturtulmuş hâli.
    private struct Match {
        /// Rota başından bu noktaya yürünen mesafe (metre).
        let travelled: Double
        /// Konumun düştüğü adımın sırası.
        let stepIndex: Int
        /// Konumun rotaya dik uzaklığı (metre).
        let distance: Double
        /// Konumun düştüğü parçanın başlangıç noktasının sırası.
        let index: Int
    }

    /// İlerleme araması mevcut konumun bu kadar ilerisine/gerisine bakar (metre).
    /// Pencere olmadan, döngünün başıyla sonunun çakıştığı yerlerde ilerleme
    /// rotanın öbür ucuna sıçrayabilir.
    private let searchAhead = 300.0
    private let searchBehind = 60.0
    /// Rota kendi kendine yaklaştığında (paralel sokaklar, döngünün kesiştiği
    /// yerler) yalnızca uzaklığa bakmak yanlış parçaya kilitlenebilir. Koşucunun
    /// gittiği yön doğru parçayı ayırır; ters yöndeki bir parçaya bu kadar
    /// metrelik ceza eklenir.
    private let courseWeight = 30.0

    private var steps: [Step] = []
    private var points: [RoutePoint] = []
    /// Her adımın rota başından başlangıç mesafesi (metre).
    private var stepStart: [Double] = []
    /// Kullanıcının bulunduğu parçanın başlangıç noktasının sırası.
    private var progressIndex = 0
    /// Rota başından bu ana kadar yürünen mesafe (metre).
    private var progressTravelled = 0.0
    /// Kullanıcının içinde bulunduğu adımın sırası.
    private var currentStepIndex = 0
    private var totalDistance = 0.0
    private var destination: CLLocationCoordinate2D?
    private var offRouteCount = 0
    private var lastReroute: ContinuousClock.Instant?
    private var isRerouting = false

    // MARK: Genel kullanım

    /// Üretilmiş döngü rotası üzerinde navigasyonu başlatır.
    func start(route: GeneratedRoute) {
        steps = makeSteps(from: route.legs, endsAtDestination: true)
        destination = route.start
        lastReroute = nil
        rebuildProgress()
    }

    /// Navigasyonu bitirir ve durumu temizler.
    func stop() {
        steps = []
        points = []
        stepStart = []
        polylines = []
        arrows = []
        destination = nil
        state = .idle
        currentInstruction = ""
        distanceToNextManeuver = 0
        remainingDistance = 0
        offRouteDistance = 0
        offRouteCount = 0
        isRerouting = false
    }

    /// Her yeni konumda çağrılır: ilerlemeyi ve talimatı günceller, varışı
    /// yakalar, rota dışına çıkışı doğrulayıp yeniden rota sürecini başlatır.
    func update(location: CLLocation) {
        guard state == .navigating, points.count > 1, isTrustworthy(location) else { return }

        let coordinate = location.coordinate
        // Kötü doğrulukta bir konum rotanın yanına düşer; eşiği o konumun kendi
        // belirsizliği kadar genişletmek gereksiz yeniden rotaları önler.
        let threshold = max(offRouteThreshold, location.horizontalAccuracy * 1.5)

        guard let match = matchOnRoute(coordinate, course: course(of: location), threshold: threshold) else { return }
        offRouteDistance = match.distance

        guard match.distance <= threshold else {
            offRouteCount += 1
            if offRouteCount >= offRouteConfirmationCount { beginReroute(from: coordinate) }
            return
        }

        offRouteCount = 0
        // İlerleme geri sarmaz; kısa GPS geri sıçramaları takibi bozmasın.
        if match.travelled > progressTravelled {
            progressTravelled = match.travelled
            progressIndex = match.index
            currentStepIndex = match.stepIndex
        }

        refreshGuidance()
        checkArrival(at: coordinate)
    }

    // MARK: Konum kalitesi

    /// Konum takibe girecek kadar güvenilir mi?
    private func isTrustworthy(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maxAcceptableAccuracy
            && abs(location.timestamp.timeIntervalSinceNow) <= maxLocationAge
    }

    /// Konumun gidiş yönü — yalnızca yön bilgisi geçerliyse ve kullanıcı
    /// gerçekten hareket ediyorsa. Dururken yön ölçümü rastgeledir.
    private func course(of location: CLLocation) -> Double? {
        guard location.courseAccuracy >= 0, location.course >= 0, location.speed > 1 else { return nil }
        return location.course
    }

    // MARK: İlerleme takibi

    /// Konumu rotanın üzerine oturtur: önce mevcut ilerlemenin çevresindeki
    /// pencerede, orada tutmazsa rotanın kalanının tamamında arar.
    private func matchOnRoute(
        _ coordinate: CLLocationCoordinate2D,
        course: Double?,
        threshold: Double
    ) -> Match? {

        let window = searchWindow()
        let near = bestMatch(for: coordinate, course: course, in: window)
        if let near, near.distance <= threshold { return near }

        // Pencerede tutmadı: GPS bir süre kesilmiş (tünel, bina arası) ya da
        // kullanıcı rotadan çıkmış olabilir. Rotanın kalanının tamamına bakılır;
        // yalnızca ileri bakıldığı için döngünün başıyla sonu karışmaz.
        guard let far = bestMatch(
            for: coordinate,
            course: course,
            in: progressIndex..<max(points.count - 1, progressIndex)
        ) else { return near }

        guard let near else { return far }
        return far.distance < near.distance ? far : near
    }

    /// Aramanın yapılacağı parça aralığı: mevcut ilerlemenin biraz gerisinden
    /// epey ilerisine.
    private func searchWindow() -> Range<Int> {
        var lower = min(progressIndex, points.count - 1)
        while lower > 0, progressTravelled - points[lower].travelled < searchBehind {
            lower -= 1
        }

        var upper = lower
        while upper < points.count - 1, points[upper].travelled - progressTravelled < searchAhead {
            upper += 1
        }
        return lower..<upper
    }

    /// Verilen parçalar içinde konuma en iyi oturan yeri bulur.
    private func bestMatch(
        for coordinate: CLLocationCoordinate2D,
        course: Double?,
        in range: Range<Int>
    ) -> Match? {

        var best: Match?
        var bestScore = Double.infinity

        for i in range {
            let (start, end) = (points[i], points[i + 1])
            let projection = Geo.project(coordinate, onto: start.coordinate, end.coordinate)

            // Puan, dik uzaklığa yön cezası eklenmiş hâli; kullanıcıya raporlanan
            // sapma ise cezasız gerçek uzaklıktır.
            let score = projection.distance + coursePenalty(course, from: start.coordinate, to: end.coordinate)
            guard score < bestScore else { continue }

            bestScore = score
            best = Match(
                travelled: start.travelled + (end.travelled - start.travelled) * projection.fraction,
                stepIndex: projection.fraction < 1 ? start.stepIndex : end.stepIndex,
                distance: projection.distance,
                index: i
            )
        }
        return best
    }

    /// Parçanın gidiş yönü kullanıcının yönünden ne kadar farklıysa o kadar ceza.
    private func coursePenalty(
        _ course: Double?,
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double {
        guard let course else { return 0 }
        return courseWeight * Geo.angularDifference(course, Geo.bearing(from: a, to: b)) / 180
    }

    /// Talimat ve mesafe alanlarını mevcut ilerlemeye göre günceller.
    private func refreshGuidance() {
        remainingDistance = max(totalDistance - progressTravelled, 0)

        // MapKit'te talimat, adımın başındaki manevrayı anlatır; gösterilecek
        // olan, bulunduğumuz adımdan sonraki ilk talimatlı adımdır.
        let upcoming = steps.indices.first {
            $0 > currentStepIndex && !steps[$0].instruction.isEmpty
        }

        if let upcoming {
            currentInstruction = steps[upcoming].instruction
            distanceToNextManeuver = max(stepStart[upcoming] - progressTravelled, 0)
        } else {
            currentInstruction = "Follow the route to the finish"
            distanceToNextManeuver = remainingDistance
        }
    }

    /// Döngü başladığı yerde bittiği için varış, hem mesafenin çoğunun
    /// yürünmüş olmasına hem bitişe yakınlığa bakar.
    private func checkArrival(at coordinate: CLLocationCoordinate2D) {
        guard let destination, progressTravelled > totalDistance * 0.5 else { return }
        guard remainingDistance <= arrivalRadius
                || Geo.distance(coordinate, destination) <= arrivalRadius else { return }

        state = .finished
        remainingDistance = 0
        distanceToNextManeuver = 0
    }

    // MARK: Yeniden rota

    /// Rota dışına çıkış doğrulandı: bekleme süresi dolduysa bağlantı rotasını
    /// çekmeye başlar. Aynı anda birden fazla istek gitmez.
    private func beginReroute(from coordinate: CLLocationCoordinate2D) {
        guard !isRerouting else { return }
        if let lastReroute, ContinuousClock.now - lastReroute < rerouteCooldown { return }

        isRerouting = true
        lastReroute = .now
        state = .rerouting
        Task { await reroute(from: coordinate) }
    }

    /// Kullanıcının konumundan, rotanın biraz ilerisindeki bir adım başlangıcına
    /// bağlantı rotası çeker ve kalan adımlarla birleştirir.
    private func reroute(from coordinate: CLLocationCoordinate2D) async {
        defer { isRerouting = false }

        // Katılım noktası bir adım başlangıcı seçilir ki bağlantı rotası eski
        // adımlarla üst üste binmeden birleşsin.
        let targetTravelled = progressTravelled + rejoinLookahead
        let rejoinIndex = steps.indices.first {
            $0 > currentStepIndex && stepStart[$0] >= targetTravelled
        } ?? steps.count - 1

        guard steps.indices.contains(rejoinIndex),
              let rejoinCoordinate = Geo.firstCoordinate(of: steps[rejoinIndex].polyline),
              let connector = await walkingRoute(from: coordinate, to: rejoinCoordinate) else {
            // Bağlantı rotası bulunamadı: eski rotayla devam et. Kullanıcı hâlâ
            // dışarıdaysa cooldown dolunca tekrar denenir.
            offRouteCount = 0
            state = .navigating
            return
        }

        steps = makeSteps(from: [connector], endsAtDestination: false) + steps[rejoinIndex...]
        rebuildProgress()
    }

    /// İki nokta arasındaki yürüme rotasını çeker; bulunamazsa `nil` döner.
    private func walkingRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .walking
        return try? await MKDirections(request: request).calculate().routes.first
    }

    // MARK: Rota kurulumu

    /// MapKit adımlarını sadeleştirir: çizgisi olmayan adımlar elenir.
    ///
    /// Döngü, uç uca eklenmiş birkaç parçadan oluşur ve her parçanın son adımı
    /// o parçanın waypoint'ine varışı anlatır ("hedefiniz solunuzda"). Rotanın
    /// ortasında bu talimat yanlış olur; geometrisi korunup metni düşürülür.
    private func makeSteps(from legs: [MKRoute], endsAtDestination: Bool) -> [Step] {
        legs.enumerated().flatMap { legIndex, leg -> [Step] in
            let isFinalLeg = legIndex == legs.count - 1
            let usable = leg.steps.filter { $0.polyline.pointCount > 1 }

            return usable.enumerated().map { stepIndex, step in
                let isWaypointArrival = stepIndex == usable.count - 1 && !(isFinalLeg && endsAtDestination)
                return Step(
                    instruction: isWaypointArrival ? "" : step.instructions,
                    polyline: step.polyline
                )
            }
        }
    }

    /// Adımlardan rota noktalarını ve mesafe tablolarını yeniden kurar;
    /// hem başlangıçta hem yeniden rota sonrasında çağrılır.
    private func rebuildProgress() {
        points = []
        stepStart = []
        var travelled = 0.0

        for (index, step) in steps.enumerated() {
            stepStart.append(travelled)

            for coordinate in Geo.coordinates(of: step.polyline) {
                if let last = points.last {
                    let segment = Geo.distance(last.coordinate, coordinate)
                    // Parçaların birleşme yerindeki tekrar eden koordinat atlanır:
                    // sıfır uzunluklu bir parçaya izdüşüm alınamaz.
                    guard segment > 0.5 else { continue }
                    travelled += segment
                }
                points.append(RoutePoint(coordinate: coordinate, stepIndex: index, travelled: travelled))
            }
        }

        totalDistance = travelled
        polylines = steps.map(\.polyline)
        arrows = RouteArrow.along(polylines)
        progressIndex = 0
        progressTravelled = 0
        currentStepIndex = 0
        offRouteCount = 0
        offRouteDistance = 0
        state = points.count > 1 ? .navigating : .idle
        refreshGuidance()
    }
}
