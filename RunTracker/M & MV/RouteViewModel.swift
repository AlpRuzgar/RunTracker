//
//  RouteViewModel.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 31.08.2026.
//

import Foundation
import MapKit

@Observable
class RouteViewModel {
    var route: MKRoute?
    var lastCalculationTime: Date?
    var lastCalculationLocation: CLLocationCoordinate2D?
    var locationManager = LocationManager()
    
    func calculateRoute(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        print("Rota çağrısı yapıldı: \(source)")
        
        if let lastTime = lastCalculationTime, let lastLoc = lastCalculationLocation{
            let timeSince = Date().timeIntervalSince(lastTime)
            let distanceSince = CLLocation(latitude: source.latitude, longitude: source.longitude)
                .distance(from: CLLocation(latitude: lastLoc.latitude, longitude: lastLoc.longitude))
            
            if timeSince < 5 && distanceSince < 30 {
                return // ne yeterli zaman ne yeterli mesafe geçti
            }
            
        }
        
        lastCalculationTime = Date()
        lastCalculationLocation = source
        
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: source.latitude, longitude: source.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        request.transportType = .walking
        
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            route = response.routes.first
            print("Rota bulundu, mesafe: \(route?.distance ?? -1)")
        } catch {
            print("HATA: \(error)")
        }
    }
}

func coordinate(from origin: CLLocationCoordinate2D, bearing: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
    let earthRadius = 6_371_000.0
    
    let bearingRad = bearing * .pi / 180
    let lat1 = origin.latitude * .pi / 180
    let lon1 = origin.longitude * .pi / 180
    
    let angularDistance = distanceMeters / earthRadius
    
    let lat2 = asin(
        sin(lat1) * cos(angularDistance) +
        cos(lat1) * sin(angularDistance) * cos(bearingRad)
    )
    
    let lon2 = lon1 + atan2(
        sin(bearingRad) * sin(angularDistance) * cos(lat1),
        cos(angularDistance) - sin(lat1) * sin(lat2)
    )
    
    return CLLocationCoordinate2D(
        latitude: lat2 * 180 / .pi,
        longitude: lon2 * 180 / .pi
    )
}

struct RouteWaypointGenerator {
    static func generateWaypoints(
        around origin: CLLocationCoordinate2D,
        targetRadius: Double, // metre
        waypointCount: Int? = nil
    ) -> [CLLocationCoordinate2D] {
        let count = waypointCount ?? Int.random(in: 3...6)
        let baseAngleStep = 360.0 / Double(count)
        let startRotation = Double.random(in: 0..<360)
        
        var waypoints: [CLLocationCoordinate2D] = []
        
        for i in 0..<count {
            let baseAngle = startRotation + baseAngleStep * Double(i)
            let angleJitter = Double.random(in: -baseAngleStep / 3...baseAngleStep / 3)
            let bearing = baseAngle + angleJitter
            
            let distanceJitter = Double.random(in: 0.7...1.3)
            let distance = targetRadius * distanceJitter
            
            let point = coordinate(from: origin, bearing: bearing, distanceMeters: distance)
            waypoints.append(point)
        }
        
        return [origin] + waypoints + [origin]
    }
}

@Observable
class RouteGeneratorViewModel {
    var isGenerating = false
    var generatedRoute: [CLLocationCoordinate2D]?
    var generatedRouteDistance: CLLocationDistance = 0 // metre

    // Başarılı rotalar burada birikir; üretim başarısız olursa (ör. Apple istek
    // limiti) sırayla bunlar gösterilir
    private var savedRoutes: [[CLLocationCoordinate2D]] = []
    private var nextSavedRouteIndex = 0
    
    func generateLoopRoute(around origin: CLLocationCoordinate2D, targetRadius: Double) async {
        isGenerating = true
        defer { isGenerating = false }
        
        let rawWaypoints = RouteWaypointGenerator.generateWaypoints(around: origin, targetRadius: targetRadius)
        var fullPath: [CLLocationCoordinate2D] = []
        var throttled = false

        for i in 0..<rawWaypoints.count - 1 {
            let from = rawWaypoints[i]
            var to = rawWaypoints[i + 1]

            var legCoordinates: [CLLocationCoordinate2D]?
            var attempts = 0

            while legCoordinates == nil && attempts < 3 && !throttled {
                attempts += 1
                switch await calculateLeg(from: from, to: to) {
                case .success(let coordinates):
                    legCoordinates = coordinates
                case .throttled:
                    // İstek limitine takıldık; devam etmek limiti daha da uzatır
                    throttled = true
                case .failed:
                    if i < rawWaypoints.count - 2 {
                        let baseAngleStep = 360.0 / Double(rawWaypoints.count - 2) // waypoint sayısı (origin'ler hariç)
                        let originalBearing = bearingBetween(origin, rawWaypoints[i + 1]) // orijinal açıyı geri hesapla
                        let bearing = originalBearing + Double.random(in: -baseAngleStep / 2...baseAngleStep / 2)
                        let distance = targetRadius * Double.random(in: 0.5...0.9) // biraz daha yakın dene
                        to = coordinate(from: origin, bearing: bearing, distanceMeters: distance)
                    }
                }
            }

            if throttled { break }

            if let legCoordinates {
                fullPath.append(contentsOf: legCoordinates)
            }
            // 3 denemede de başarısız olursa, bu bacağı tamamen atla, döngü devam etsin
        }
        
        func bearingBetween(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
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
        
        let cleanedPath = removingOverlaps(from: fullPath)

        // Başlangıca dönmeyen veya limit yüzünden yarım kalan rotaları eleme
        if !throttled, returnsToStart(cleanedPath, origin: origin) {
            generatedRoute = cleanedPath
            generatedRouteDistance = totalDistance(of: cleanedPath)
            savedRoutes.append(cleanedPath)
        } else {
            // Yeni rota üretilemedi; mevcut konumdan başlayan kayıtlı rotalar arasında sırayla dön
            for _ in 0..<savedRoutes.count {
                let candidate = savedRoutes[nextSavedRouteIndex % savedRoutes.count]
                nextSavedRouteIndex += 1
                if returnsToStart(candidate, origin: origin) {
                    generatedRoute = candidate
                    generatedRouteDistance = totalDistance(of: candidate)
                    return
                }
            }
            generatedRoute = nil
            generatedRouteDistance = 0
        }
    }

    /// Rotanın başlangıç noktasından başlayıp yine oraya dönüp dönmediğini kontrol eder.
    /// MKDirections koordinatları yola oturttuğu için birebir eşitlik yerine tolerans kullanılır.
    func returnsToStart(
        _ path: [CLLocationCoordinate2D],
        origin: CLLocationCoordinate2D,
        tolerance: CLLocationDistance = 50
    ) -> Bool {
        guard let first = path.first, let last = path.last else { return false }
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let startGap = CLLocation(latitude: first.latitude, longitude: first.longitude).distance(from: originLocation)
        let endGap = CLLocation(latitude: last.latitude, longitude: last.longitude).distance(from: originLocation)
        return startGap <= tolerance && endGap <= tolerance
    }

    /// Rota üzerindeki ardışık noktalar arası mesafelerin toplamı (metre)
    func totalDistance(of path: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard path.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for i in 1..<path.count {
            total += CLLocation(latitude: path[i].latitude, longitude: path[i].longitude)
                .distance(from: CLLocation(latitude: path[i - 1].latitude, longitude: path[i - 1].longitude))
        }
        return total
    }

    /// Rotanın kendisiyle çakışan (aynı yoldan gidip geri dönen veya kendini kesen) bölümlerini bulur ve keser.
    /// İki nokta birbirine `proximityThreshold`'dan yakınsa ama aralarında rota boyunca
    /// `minimumLoopLength`'ten fazla mesafe varsa, aradaki bölüm çakışma sayılır ve atlanır.
    func removingOverlaps(
        from path: [CLLocationCoordinate2D],
        proximityThreshold: CLLocationDistance = 25,
        minimumLoopLength: CLLocationDistance = 10
    ) -> [CLLocationCoordinate2D] {
        guard path.count > 2 else { return path }

        let locations = path.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }

        // Her noktanın rota başından itibaren kat edilen mesafesi
        var cumulativeDistance: [CLLocationDistance] = [0]
        for i in 1..<locations.count {
            cumulativeDistance.append(cumulativeDistance[i - 1] + locations[i].distance(from: locations[i - 1]))
        }
        let totalDistance = cumulativeDistance[locations.count - 1]

        var result: [CLLocationCoordinate2D] = []
        var i = 0
        while i < path.count {
            result.append(path[i])

            var next = i + 1
            // Sondan geriye tarayarak en büyük çakışmayı tek seferde kes
            var j = path.count - 1
            while j > i {
                let travelBetween = cumulativeDistance[j] - cumulativeDistance[i]
                if travelBetween < minimumLoopLength { break }

                // Rotanın yarısından fazlasını kesme; başlangıç ve bitiş aynı nokta
                // olduğu için tüm döngü yanlışlıkla silinmesin
                if travelBetween < totalDistance / 2,
                   locations[i].distance(from: locations[j]) < proximityThreshold {
                    next = j
                    break
                }
                j -= 1
            }
            i = next
        }
        return result
    }
    
    private enum LegResult {
        case success([CLLocationCoordinate2D])
        case failed    // rota bulunamadı, başka waypoint denenebilir
        case throttled // Apple istek limiti; denemeye devam etmek anlamsız
    }

    private func calculateLeg(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> LegResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .walking

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else { return .failed }
            return .success(route.polyline.coordinates)
        } catch {
            if let mkError = error as? MKError, mkError.code == .loadingThrottled {
                print("MKDirections istek limiti aşıldı: \(error)")
                return .throttled
            }
            print("Bacak hesaplanamadı: \(error)")
            return .failed
        }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
