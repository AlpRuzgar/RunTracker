//
//  RouteArrow.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Yön oku

/// Rota üzerinde tek bir yön oku: nereye çizileceği ve rotanın orada hangi
/// yöne gittiği. Döngü rotalarında çizginin kendisi hangi yöne koşulacağını
/// göstermediği için oklar bu bilgiyi taşır.
struct RouteArrow: Identifiable, Equatable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    /// Gidiş yönü (0–360 derece, kuzeyden saat yönünde).
    let heading: Double

    static func == (lhs: RouteArrow, rhs: RouteArrow) -> Bool { lhs.id == rhs.id }
}

extension RouteArrow {

    /// Rotayı fazla kalabalıklaştırmadan yönü izlenebilir kılan ok sayısı.
    private static let preferredCount = 14.0
    private static let minimumSpacing = 120.0
    private static let maximumSpacing = 400.0
    /// Okun yönü, çizginin bu yarıçaptaki iki noktası arasından okunur; tek bir
    /// kısa parçanın açısı kaldırım kıvrımlarıyla oynadığı için yanıltıcı olur.
    private static let headingSpan = 10.0

    /// Verilen çizgiler boyunca yaklaşık eşit aralıklı yön okları üretir.
    /// `spacing` verilmezse rotanın uzunluğuna göre seçilir.
    static func along(_ polylines: [MKPolyline], spacing: Double? = nil) -> [RouteArrow] {
        let path = MeasuredPath(Geo.joinedCoordinates(of: polylines))
        guard path.length > 0 else { return [] }

        let step = spacing ?? min(max(path.length / preferredCount, minimumSpacing), maximumSpacing)

        // İlk ok yarım aralık ileride: başlangıç noktasındaki işaretle çakışmaz.
        return stride(from: step / 2, to: path.length, by: step).map { travelled in
            RouteArrow(
                coordinate: path.coordinate(at: travelled),
                heading: Geo.bearing(
                    from: path.coordinate(at: travelled - headingSpan),
                    to: path.coordinate(at: travelled + headingSpan)
                )
            )
        }
    }
}

// MARK: - Mesafeye göre okunabilen çizgi

/// Koordinat dizisini "başından şu kadar metre ileride hangi nokta var?"
/// sorusuna cevap verebilecek şekilde saklar.
private struct MeasuredPath {
    private let coordinates: [CLLocationCoordinate2D]
    /// `travelled[i]`, dizinin başından `coordinates[i]`ye yürünen mesafe.
    private let travelled: [Double]

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

        guard let next = travelled.firstIndex(where: { $0 >= distance }), next > 0 else { return first }
        let segment = travelled[next] - travelled[next - 1]
        let fraction = segment > 0 ? (distance - travelled[next - 1]) / segment : 0

        return Geo.interpolate(from: coordinates[next - 1], to: coordinates[next], fraction: fraction)
    }
}

// MARK: - Harita katmanı

/// Yön oklarını haritaya yerleştirir.
///
/// Ok simgeleri harita değil ekran ile hizalı çizildiği için, harita
/// döndürüldüğünde (pusula modu, 3B eğim) oklar aynı miktarda geri döndürülür;
/// böylece hep gerçek gidiş yönünü gösterirler.
struct RouteDirectionArrows: MapContent {
    let arrows: [RouteArrow]
    /// Haritanın kuzeye göre dönüklüğü (derece) — `onMapCameraChange`'den gelir.
    var mapHeading: Double = 0
    var tint: Color = .blue

    var body: some MapContent {
        ForEach(arrows) { arrow in
            Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(tint.gradient, in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                    .rotationEffect(.degrees(arrow.heading - mapHeading))
                    .shadow(radius: 1)
            }
            .annotationTitles(.hidden)
        }
    }
}
