//
//  RunNavigationViewModel.swift
//  RunTracker
//

import Foundation
import MapKit

@Observable
class RunNavigationViewModel {
    enum NavigationState {
        case idle
        case navigating
        case paused
    }

    var state: NavigationState = .idle
    var selectedRoute: [CLLocationCoordinate2D]?
    var instruction = ""
    var traveledDistance: CLLocationDistance = 0 // metre
    var remainingDistance: CLLocationDistance = 0 // metre
    var traveledPath: [CLLocationCoordinate2D] = []
    var isRerouting = false

    private var routeIndex = 0 // rota üzerinde ulaşılan son noktanın indeksi
    private var startDate: Date?
    private var accumulatedTime: TimeInterval = 0 // duraklatmalar öncesi biriken süre
    private var lastResumeDate: Date?
    private var lastLocation: CLLocation?
    private var offRouteUpdateCount = 0

    private let onRouteThreshold: CLLocationDistance = 40 // bundan uzaksa rotadan çıkmış sayılır
    private let offRouteUpdateLimit = 3 // arka arkaya bu kadar güncelleme uzaksa yeniden rota çiz
    private let progressSearchWindow: CLLocationDistance = 250 // ilerleme ararken en fazla bu kadar ileri bak

    /// Duraklatmalar hariç geçen toplam süre
    var elapsedTime: TimeInterval {
        guard let lastResumeDate, state == .navigating else { return accumulatedTime }
        return accumulatedTime + Date().timeIntervalSince(lastResumeDate)
    }

    func selectRoute(_ route: [CLLocationCoordinate2D]) {
        selectedRoute = route
        remainingDistance = pathDistance(route, from: 0)
    }

    func start() {
        guard selectedRoute != nil else { return }
        routeIndex = 0
        traveledDistance = 0
        traveledPath = []
        accumulatedTime = 0
        lastLocation = nil
        offRouteUpdateCount = 0
        startDate = Date()
        lastResumeDate = startDate
        instruction = "Rotayı takip edin"
        state = .navigating
    }

    func togglePause() {
        switch state {
        case .navigating:
            accumulatedTime = elapsedTime
            lastResumeDate = nil
            lastLocation = nil // devam edince mesafe sıçramasın
            state = .paused
        case .paused:
            lastResumeDate = Date()
            state = .navigating
        case .idle:
            break
        }
    }

    /// Navigasyonu bitirir ve koşuyu Run olarak döndürür
    func stop() -> Run? {
        guard let startDate else { return nil }
        let run = Run(route: traveledPath, date: startDate, distance: traveledDistance, duration: elapsedTime)

        state = .idle
        self.startDate = nil
        lastResumeDate = nil
        lastLocation = nil
        selectedRoute = nil
        instruction = ""
        return run
    }

    /// Her konum güncellemesinde çağrılır: ilerlemeyi, talimatı ve rotadan çıkma durumunu günceller
    func update(with coordinate: CLLocationCoordinate2D) async {
        guard state == .navigating, !isRerouting,
              let route = selectedRoute, route.count > 1 else { return }

        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let lastLocation {
            traveledDistance += userLocation.distance(from: lastLocation)
        }
        lastLocation = userLocation
        traveledPath.append(coordinate)

        // İleriye dönük sınırlı pencerede en yakın rota noktasını bul.
        // Pencere sınırlı; yoksa döngü rotasında bitiş noktası da başlangıca
        // yakın olduğu için ilerleme bir anda sona atlar.
        var nearestIndex = routeIndex
        var nearestDistance = CLLocationDistance.greatestFiniteMagnitude
        var windowTravel: CLLocationDistance = 0
        for i in routeIndex..<route.count {
            if i > routeIndex {
                windowTravel += distanceBetween(route[i - 1], route[i])
                if windowTravel > progressSearchWindow { break }
            }
            let d = userLocation.distance(from: CLLocation(latitude: route[i].latitude, longitude: route[i].longitude))
            if d < nearestDistance {
                nearestDistance = d
                nearestIndex = i
            }
        }

        // Rotadan çıkma kontrolü
        if nearestDistance > onRouteThreshold {
            offRouteUpdateCount += 1
            if offRouteUpdateCount >= offRouteUpdateLimit {
                await reroute(from: coordinate)
            } else {
                instruction = "Rotadan uzaklaşıyorsunuz"
            }
            return
        }

        offRouteUpdateCount = 0
        routeIndex = nearestIndex
        remainingDistance = nearestDistance + pathDistance(route, from: routeIndex)

        if routeIndex >= route.count - 2 || remainingDistance < 20 {
            instruction = "Başlangıç noktasına ulaştınız 🎉"
            return
        }

        instruction = upcomingTurnInstruction(on: route)
    }

    /// Kullanıcı rotadan çıktığında mevcut konumdan rotanın kalanına yeni bir bağlantı hesaplar
    private func reroute(from coordinate: CLLocationCoordinate2D) async {
        guard let route = selectedRoute else { return }
        isRerouting = true
        defer { isRerouting = false }
        instruction = "Rota yeniden hesaplanıyor..."

        // Rotaya, kalınan noktanın biraz ilerisinden bağlan
        let rejoinIndex = min(routeIndex + 5, route.count - 1)
        let target = route[rejoinIndex]

        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: target.latitude, longitude: target.longitude), address: nil)
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let newLeg = response.routes.first?.polyline.coordinates else { return }
            selectedRoute = newLeg + Array(route[rejoinIndex...])
            routeIndex = 0
            offRouteUpdateCount = 0
            instruction = "Yeni rota hesaplandı"
        } catch {
            print("Yeniden rota hesaplanamadı: \(error)")
            instruction = "Rotaya geri dönün"
        }
    }

    /// İleride yaklaşan ilk belirgin dönüş için talimat üretir
    private func upcomingTurnInstruction(on route: [CLLocationCoordinate2D]) -> String {
        // GPS/çizim gürültüsünü azaltmak için ~8 m aralıklarla örneklenmiş ileri bakış listesi
        var samples: [CLLocationCoordinate2D] = [route[routeIndex]]
        var sampleTravel: [CLLocationDistance] = [0]
        var travelled: CLLocationDistance = 0
        var last = route[routeIndex]

        var i = routeIndex + 1
        while i < route.count, travelled < 200 {
            let d = distanceBetween(last, route[i])
            if d >= 8 {
                travelled += d
                samples.append(route[i])
                sampleTravel.append(travelled)
                last = route[i]
            }
            i += 1
        }

        guard samples.count >= 3 else { return "Düz devam et" }

        for k in 1..<samples.count - 1 {
            let incoming = bearingDegrees(from: samples[k - 1], to: samples[k])
            let outgoing = bearingDegrees(from: samples[k], to: samples[k + 1])
            let turn = normalizedAngle(outgoing - incoming)

            if abs(turn) > 35 {
                let direction = turn > 0 ? "sağa" : "sola"
                let distance = sampleTravel[k]
                if distance < 20 {
                    return "Şimdi \(direction) dön"
                }
                return "\(Int(distance / 10) * 10) m sonra \(direction) dön"
            }
        }
        return "Düz devam et"
    }

    /// Rotanın verilen indeksten sonuna kadar olan uzunluğu
    private func pathDistance(_ route: [CLLocationCoordinate2D], from index: Int) -> CLLocationDistance {
        guard index < route.count - 1 else { return 0 }
        var total: CLLocationDistance = 0
        for i in index..<(route.count - 1) {
            total += distanceBetween(route[i], route[i + 1])
        }
        return total
    }

    private func distanceBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180

        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Açıyı -180...180 aralığına indirger (pozitif: sağ, negatif: sol)
    private func normalizedAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a < -180 { a += 360 }
        return a
    }
}
