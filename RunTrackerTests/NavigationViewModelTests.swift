//
//  NavigationViewModelTests.swift
//  RunTrackerTests
//
//  Created by Alp Rüzgar on 22.09.2026.
//

import Testing
import MapKit
import CoreLocation
@testable import RunTracker

// Rotaya katılma, başlama eşiği ve ters yön. Hiçbiri ağa dokunmaz: talimatsız
// bir yol verildiği için MapKit'e yalnızca yeniden rota çekerken gidilir, bu
// testlerde ise kullanıcı rotanın dışına hiç çıkmaz.

private let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)

private func point(east: Double, north: Double) -> CLLocationCoordinate2D {
    Geo.move(from: origin, east: east, north: north)
}

/// Talimat taşımayan sahte yol; kaydedilmiş bir koşu yolu gibi davranır.
private struct StubPath: FollowablePath {
    let polylines: [MKPolyline]
    let legs: [MKRoute] = []
    let destination: CLLocationCoordinate2D?
    let startCoordinate: CLLocationCoordinate2D? = nil
    let distance: Double
}

/// Kenarı 400 m olan kare döngü: başladığı yerde biter, toplam 1600 m.
/// Köşeleri sırayla (0,0) → (400,0) → (400,400) → (0,400) → (0,0).
private func squareLoop() -> StubPath {
    let corners = [
        point(east: 0, north: 0),
        point(east: 400, north: 0),
        point(east: 400, north: 400),
        point(east: 0, north: 400),
        point(east: 0, north: 0),
    ]
    return StubPath(
        polylines: [MKPolyline(coordinates: corners, count: corners.count)],
        destination: corners.first,
        distance: 1600
    )
}

/// Takibe girecek kadar güvenilir bir konum. Yön geçersiz (-1) bırakılır:
/// duran bir koşucuda olduğu gibi eşleştirmeye yön cezası karışmaz.
private func location(_ coordinate: CLLocationCoordinate2D, accuracy: Double = 5) -> CLLocation {
    CLLocation(
        coordinate: coordinate,
        altitude: 0,
        horizontalAccuracy: accuracy,
        verticalAccuracy: 1,
        course: -1,
        speed: 0,
        timestamp: .now
    )
}

/// Kare döngünün kenar uzunluğu düzlem yaklaşımıyla birkaç metre oynayabilir.
private let tolerance = 20.0

// MARK: - Başlama eşiği

@MainActor
struct NavigationStartTests {

    @Test func waitsInsteadOfStartingWhenFarFromTheRoute() {
        let navigation = NavigationViewModel()
        navigation.start(path: squareLoop())
        #expect(navigation.state == .waitingToStart)

        navigation.update(location: location(point(east: 200, north: -500)))

        #expect(navigation.state == .waitingToStart)
        #expect((navigation.distanceToRoute ?? 0) > 400)
    }

    @Test func distanceToRouteIsUnknownUntilTheFirstFix() {
        let navigation = NavigationViewModel()
        navigation.start(path: squareLoop())

        // "Ölçülmedi" ile "rotanın üstünde" karışırsa ekran konum gelmeden
        // "0 m uzakta" yazar.
        #expect(navigation.distanceToRoute == nil)
    }

    @Test func startsByItselfOnceTheUserReachesTheRoute() {
        let navigation = NavigationViewModel()
        navigation.start(path: squareLoop())

        navigation.update(location: location(point(east: 200, north: -500)))
        #expect(navigation.state == .waitingToStart)

        navigation.update(location: location(point(east: 200, north: -10)))
        #expect(navigation.state == .navigating)
    }

    @Test func badlyMeasuredLocationsNeverStartTheRun() {
        let navigation = NavigationViewModel()
        navigation.start(path: squareLoop())

        // Rotanın tam üstünde ama doğruluğu `maxAcceptableAccuracy`nin ötesinde.
        navigation.update(location: location(point(east: 200, north: 0), accuracy: 120))

        #expect(navigation.state == .waitingToStart)
        #expect(navigation.distanceToRoute == nil)
    }
}

// MARK: - Rotanın ortasından katılma

@MainActor
struct NavigationEntryTests {

    @Test func joiningMidRouteOnlyCountsTheDistanceToTheFinish() {
        let navigation = NavigationViewModel()
        navigation.start(path: squareLoop())

        // İkinci kenarın ortası: rota başından 600 m, bitişe 1000 m.
        navigation.update(location: location(point(east: 400, north: 200)))

        #expect(navigation.state == .navigating)
        #expect(abs(navigation.remainingDistance - 1000) < tolerance)
        #expect(abs(navigation.journeyDistance - 1000) < tolerance)
    }

    @Test func progressStartsEmptyWhenJoiningMidRoute() {
        let navigation = NavigationViewModel()
        navigation.start(path: squareLoop())

        navigation.update(location: location(point(east: 400, north: 200)))

        // Rotanın %37'sinden katıldı ama kendisi henüz bir adım atmadı.
        #expect(navigation.progressFraction < 0.01)
    }

    @Test func standingAtTheStartRunsTheWholeLoop() {
        let navigation = NavigationViewModel()
        navigation.start(path: squareLoop())

        // Döngünün başı ile sonu AYNI noktadır. Eşleştirme sona oturursa koşu
        // daha başlamadan "tamamlandı" sayılır.
        navigation.update(location: location(point(east: 0, north: 0)))

        #expect(navigation.state == .navigating)
        #expect(abs(navigation.journeyDistance - 1600) < tolerance)
        #expect(navigation.progressFraction < 0.01)
    }

    @Test func reachesTheFinishAfterJoiningMidRoute() {
        let navigation = NavigationViewModel()
        navigation.start(path: squareLoop())

        navigation.update(location: location(point(east: 400, north: 200)))
        for coordinate in [
            point(east: 400, north: 400),
            point(east: 0, north: 400),
            point(east: 0, north: 0),
        ] {
            navigation.update(location: location(coordinate))
        }

        #expect(navigation.state == .finished)
        #expect(navigation.progressFraction > 0.99)
    }
}

// MARK: - Ters yön

@MainActor
struct ReversedPathTests {

    @Test func reversedPathKeepsTheLineAndFlipsItsEnds() {
        let loop = squareLoop()
        let reversed = loop.reversed()

        let forward = Geo.joinedCoordinates(of: loop.polylines)
        let backward = Geo.joinedCoordinates(of: reversed.polylines)

        #expect(backward.count == forward.count)
        #expect(Geo.distance(backward.first!, forward.last!) < 0.5)
        #expect(Geo.distance(backward.last!, forward.first!) < 0.5)
        #expect(abs(reversed.distance - loop.distance) < 0.001)
    }

    @Test func reversedPathFinishesWhereTheForwardPathBegan() throws {
        let loop = squareLoop()
        let destination = try #require(loop.reversed().destination)

        #expect(Geo.distance(destination, try #require(loop.destination)) < 0.5)
    }

    @Test func reversedPathCarriesNoTurnInstructions() {
        // MKRoute'un adımları yönlüdür; ters çevrilemedikleri için düşürülür.
        #expect(squareLoop().reversed().legs.isEmpty)
    }

    @Test func reversedRouteMeasuresTheOppositeRemainingDistance() {
        let navigation = NavigationViewModel()
        navigation.start(path: squareLoop().reversed())

        // Aynı nokta: ileri yönde bitişe 1000 m vardı, ters yönde 600 m kalır.
        navigation.update(location: location(point(east: 400, north: 200)))

        #expect(navigation.state == .navigating)
        #expect(abs(navigation.remainingDistance - 600) < tolerance)
    }
}
