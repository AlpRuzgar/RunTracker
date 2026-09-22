//
//  RouteSegment.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 9.09.2026.
//

import Foundation
import CoreLocation
import MapKit

nonisolated struct RoutePoint: Codable {
    var latitude: Double
    var longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Duraklamalarla bölünen, kesintisiz koşulan tek bir parça.
nonisolated struct RouteSegment: Codable {
    var points: [RoutePoint]
}

extension Array where Element == RouteSegment {
    /// Parçaların harita çizgileri. Duraklamayla bölünmüş yol tek bir çizgide
    /// birleştirilmez: aradaki boşluk düz bir çizgiyle bağlanmış görünürdü.
    var polylines: [MKPolyline] {
        map { segment in
            let coordinates = segment.points.map(\.coordinate)
            return MKPolyline(coordinates: coordinates, count: coordinates.count)
        }
    }
}
