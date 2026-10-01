//
//  Geo.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import Foundation
import MapKit
import CoreLocation

/// Rota üretimi ve navigasyonun ortak geometri yardımcıları.
///
/// Şehir ölçeğindeki mesafelerde (birkaç kilometre) enlem/boylam farkını doğu
/// ve kuzey yönünde metreye çeviren düzlemsel yaklaşım kullanılır: hata
/// milimetre mertebesinde kalır, hesap ise küresel formüllerden çok daha ucuzdur.
/// Yalnızca yeni bir noktaya "yürüme" işlemi (`destination`) küresel yapılır.
nonisolated enum Geo {
    static let earthRadius = 6_371_000.0

    // MARK: Ölçüm

    /// `a`dan `b`ye olan farkın metre cinsinden doğu/kuzey bileşenleri.
    static func offset(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> (east: Double, north: Double) {
        let meanLatitude = (a.latitude + b.latitude) / 2 * .pi / 180
        return (
            east: (b.longitude - a.longitude) * .pi / 180 * cos(meanLatitude) * earthRadius,
            north: (b.latitude - a.latitude) * .pi / 180 * earthRadius
        )
    }

    /// İki koordinat arası mesafe (metre).
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let delta = offset(from: a, to: b)
        return hypot(delta.east, delta.north)
    }

    /// `a` noktasından `b` noktasına bakış yönü (0–360 derece, kuzeyden saat yönünde).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let delta = offset(from: a, to: b)
        let degrees = atan2(delta.east, delta.north) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// İki yön arasındaki en küçük açı farkı (0–180 derece).
    static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return difference > 180 ? 360 - difference : difference
    }

    // MARK: Nokta üretme

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

    /// İki nokta arasında oransal ara nokta. Kısa parçalarda doğrusal ara
    /// değer küresel hesapla ayırt edilemez.
    static func interpolate(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
    }

    /// Koordinat dizisinin uç uca uzunluğu (metre).
    static func length(of coordinates: [CLLocationCoordinate2D]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    // MARK: İzdüşüm

    /// Bir noktanın `a`–`b` doğru parçası üzerindeki izdüşümü: parçanın
    /// neresine düştüğü (0–1) ve parçaya dik uzaklığı (metre).
    ///
    /// En yakın *köşeye* olan uzaklık yerine parçaya olan dik uzaklığı ölçmek,
    /// konumun rota üzerindeki yerini örnekleme aralığına yuvarlamadan verir.
    static func project(
        _ point: CLLocationCoordinate2D,
        onto a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> (fraction: Double, distance: Double) {

        let segment = offset(from: a, to: b)
        let relative = offset(from: a, to: point)
        let lengthSquared = segment.east * segment.east + segment.north * segment.north

        guard lengthSquared > 0 else { return (0, hypot(relative.east, relative.north)) }

        let fraction = min(max((relative.east * segment.east + relative.north * segment.north) / lengthSquared, 0), 1)
        return (
            fraction,
            hypot(relative.east - fraction * segment.east, relative.north - fraction * segment.north)
        )
    }

    // MARK: Çizgiler

    static func coordinates(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return coordinates
    }

    static func firstCoordinate(of polyline: MKPolyline) -> CLLocationCoordinate2D? {
        guard polyline.pointCount > 0 else { return nil }
        return polyline.coordinate(at: 0)
    }

    static func lastCoordinate(of polyline: MKPolyline) -> CLLocationCoordinate2D? {
        guard polyline.pointCount > 0 else { return nil }
        return polyline.coordinate(at: polyline.pointCount - 1)
    }

    /// Ardışık çizgileri tek bir koordinat dizisine ekler; parçaların birleşme
    /// noktasındaki tekrar eden koordinatlar atlanır.
    static func joinedCoordinates(of polylines: [MKPolyline]) -> [CLLocationCoordinate2D] {
        var joined: [CLLocationCoordinate2D] = []
        for polyline in polylines {
            for coordinate in coordinates(of: polyline) {
                if let last = joined.last, distance(last, coordinate) < 0.5 { continue }
                joined.append(coordinate)
            }
        }
        return joined
    }
}

// MARK: - Mesafeye göre okunabilen çizgi

/// Koordinat dizisini "başından şu kadar metre ileride hangi nokta var?"
/// sorusuna cevap verebilecek şekilde saklar. Yön okları (`RouteArrow`) ve rota
/// izinin eşit aralıklı örnekleri (`RouteFootprint`) aynı ölçümü kullanır.
nonisolated struct MeasuredPath {
    let coordinates: [CLLocationCoordinate2D]
    /// `travelled[i]`, dizinin başından `coordinates[i]`ye yürünen mesafe.
    let travelled: [Double]

    var length: Double { travelled.last ?? 0 }

    init(_ coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates

        var total = 0.0
        var distances = coordinates.isEmpty ? [] : [0.0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            total += Geo.distance(a, b)
            distances.append(total)
        }
        self.travelled = distances
    }

    /// Çizginin başından `distance` metre ileride kalan nokta; dışarıda kalan
    /// mesafeler uçlara kırpılır.
    func coordinate(at distance: Double) -> CLLocationCoordinate2D {
        guard let first = coordinates.first, let last = coordinates.last else {
            return CLLocationCoordinate2D()
        }
        guard distance > 0 else { return first }
        guard distance < length else { return last }

        // İkili arama: `travelled` artan sıralıdır. Rota izi yüzlerce örneği
        // tek tek sorduğu için doğrusal arama çizgi uzadıkça karesel büyürdü.
        var low = 1
        var high = travelled.count - 1
        while low < high {
            let mid = (low + high) / 2
            if travelled[mid] >= distance { high = mid } else { low = mid + 1 }
        }
        let next = low
        let segment = travelled[next] - travelled[next - 1]
        let fraction = segment > 0 ? (distance - travelled[next - 1]) / segment : 0

        return Geo.interpolate(from: coordinates[next - 1], to: coordinates[next], fraction: fraction)
    }

    /// Çizgi boyunca `step` metre aralıklı noktalar; ilki çizginin başı.
    func samples(every step: Double) -> [CLLocationCoordinate2D] {
        guard !coordinates.isEmpty else { return [] }
        return stride(from: 0, through: length, by: step).map(coordinate(at:))
    }
}

private nonisolated extension MKPolyline {
    /// Tek bir koordinatı tüm diziyi kopyalamadan okur.
    func coordinate(at index: Int) -> CLLocationCoordinate2D {
        var coordinate = CLLocationCoordinate2D()
        getCoordinates(&coordinate, range: NSRange(location: index, length: 1))
        return coordinate
    }
}
