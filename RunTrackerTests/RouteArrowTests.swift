//
//  RouteArrowTests.swift
//  RunTrackerTests
//
//  Created by Alp Rüzgar on 22.09.2026.
//

import Testing
import MapKit
import CoreLocation
@testable import RunTracker

// Yön okları: sıklık, kimlik kararlılığı ve gösterdikleri yön.

private let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)

private func point(east: Double, north: Double) -> CLLocationCoordinate2D {
    Geo.move(from: origin, east: east, north: north)
}

/// Kuzeye doğru 2 km'lik düz bir çizgi.
private func straightNorth() -> [MKPolyline] {
    let coordinates = stride(from: 0.0, through: 2000.0, by: 100.0).map {
        point(east: 0, north: $0)
    }
    return [MKPolyline(coordinates: coordinates, count: coordinates.count)]
}

private struct StubPath: FollowablePath {
    let polylines: [MKPolyline]
    let legs: [MKRoute] = []
    let destination: CLLocationCoordinate2D?
    let startCoordinate: CLLocationCoordinate2D? = nil
    let distance: Double
}

@MainActor
struct RouteArrowTests {

    @Test func sameRouteProducesIdenticalArrows() {
        // Kimlik rastgele olsaydı iki hesap asla eşit çıkmaz, harita da kamera
        // her oynadığında bütün okları söküp yeniden kurardı.
        #expect(RouteArrow.along(straightNorth()) == RouteArrow.along(straightNorth()))
    }

    @Test func compactDensityDrawsFewerArrows() {
        let route = straightNorth()

        let standard = RouteArrow.along(route)
        let sparse = RouteArrow.sparse(along: route)

        #expect(sparse.count < standard.count)
        #expect(!sparse.isEmpty)
    }

    @Test func arrowsPointAlongTheRoute() throws {
        let arrow = try #require(RouteArrow.along(straightNorth()).first)

        // Kuzeye giden rotada oklar kuzeyi gösterir.
        #expect(Geo.angularDifference(arrow.heading, 0) < 1)
    }

    @Test func reversedRouteArrowsPointTheOtherWay() throws {
        let path = StubPath(polylines: straightNorth(), destination: nil, distance: 2000)
        let arrow = try #require(RouteArrow.along(path.reversed().polylines).first)

        // Aynı çizgi, ters yön: oklar güneyi göstermeli. Ters yönde çizgi ileri
        // yöndekiyle birebir aynı olduğu için yönü SADECE oklar taşır.
        #expect(Geo.angularDifference(arrow.heading, 180) < 1)
    }
}
