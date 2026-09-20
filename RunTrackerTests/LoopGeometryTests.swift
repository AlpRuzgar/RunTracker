//
//  LoopGeometryTests.swift
//  RunTrackerTests
//
//  Created by Alp Rüzgar on 15.09.2026.
//

import Testing
import CoreLocation
@testable import RunTracker

// Rota üretiminin ağdan bağımsız kısmı: yakınsama, şekil, yön ve benzerlik.
// Hiçbiri MapKit'e dokunmaz; ağın yerini sentetik mesafe fonksiyonları alır.

private let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)

private func point(east: Double, north: Double) -> CLLocationCoordinate2D {
    Geo.move(from: origin, east: east, north: north)
}

/// Düz çizgilerden oluşan bir yol: her köşe arasına ara nokta konmaz;
/// `RouteFootprint` zaten eşit aralıklarla örnekler.
private func path(_ corners: [(Double, Double)]) -> [CLLocationCoordinate2D] {
    corners.map { point(east: $0.0, north: $0.1) }
}

// MARK: - Yakınsama

struct RadiusSolverTests {
    private let target = 5_000.0
    private let unitPerimeter = 6.0

    private func solver(maxEvaluations: Int = 3) -> RadiusSolver {
        RadiusSolver(
            target: target,
            initialRadius: target / (DetourEstimate.initial * unitPerimeter),
            tolerance: 0.10,
            maxEvaluations: maxEvaluations
        )
    }

    /// Dolambaç katsayısı sabitken (D = k · r · P₁) orantısal adım kökü tek
    /// düzeltmede tam bulur — ilk tahmin %23 yanlış olsa bile.
    @Test func proportionalStepSolvesConstantDetourInOneCorrection() throws {
        var solver = solver()
        while let radius = solver.nextRadius {
            solver.record(radius: radius, distance: 1.6 * radius * unitPerimeter)
        }

        #expect(solver.samples.count == 2)
        #expect(abs(solver.relativeError(of: solver.samples[0])) > 0.2)
        let best = try #require(solver.best)
        #expect(abs(solver.relativeError(of: best)) < 1e-9)
    }

    /// k yarıçapla değişiyorsa hata her adımda yaklaşık esneklik (ε = d ln k / d ln r)
    /// kadar küçülür. Burada k = 1.2 + 0.0004·r, bu aralıkta ε ≈ 0.15.
    @Test func errorShrinksByDetourElasticityPerStep() throws {
        var solver = solver()
        while let radius = solver.nextRadius {
            solver.record(radius: radius, distance: (1.2 + 0.0004 * radius) * radius * unitPerimeter)
        }

        #expect(solver.isConverged)
        #expect(solver.samples.count <= 3)
        let first = abs(solver.relativeError(of: solver.samples[0]))
        let second = abs(solver.relativeError(of: solver.samples[1]))
        #expect(second <= 0.25 * first)
    }

    /// Süreksiz ağ: D hedefin iki yanına sıçrıyor ve orantısal adım aralığın
    /// dışına düşüyor. Çözücü aralığın ortasını dener, tur hakkında durur ve
    /// en yakın ölçümü döner — sonsuza kadar salınmaz.
    @Test func fallsBackToBisectionWhenNetworkJumps() throws {
        var solver = solver()
        while let radius = solver.nextRadius {
            solver.record(radius: radius, distance: radius < 600 ? 2_000 : 6_500)
        }

        #expect(solver.samples.count == 3)
        #expect(!solver.isConverged)
        #expect(solver.nextRadius == nil)

        let (first, second, third) = (solver.samples[0], solver.samples[1], solver.samples[2])
        #expect(abs(third.radius - (first.radius + second.radius) / 2) < 1e-9)
        #expect(try #require(solver.best).distance == 6_500)
    }

    @Test func sameMeasurementsGiveSameRadii() {
        func radii() -> [Double] {
            var solver = solver(maxEvaluations: 4)
            while let radius = solver.nextRadius {
                solver.record(radius: radius, distance: radius < 550 ? 3_900 : 6_200)
            }
            return solver.samples.map(\.radius)
        }
        #expect(radii() == radii())
    }
}

// MARK: - Şekil

struct LoopShapeTests {
    private func shape(seed: UInt64, bearing: Double = 40) -> LoopShape {
        var random = SeededRandom(seed: seed)
        return LoopShape.loop(openingBearing: bearing, vertexCountRange: 4...6, using: &random)
    }

    /// Şekil başlangıç etrafında ölçeklenir: yarıçapı iki katına çıkarmak her
    /// waypoint'in başlangıca göre ofsetini iki katına çıkarır. Yakınsamanın
    /// "tek değişken" varsayımı buna dayanır.
    @Test func scalesAroundStartPoint() {
        let shape = shape(seed: 7)
        let near = shape.waypoints(from: origin, radius: 400)
        let far = shape.waypoints(from: origin, radius: 800)

        for (a, b) in zip(near, far) {
            let small = Geo.offset(from: origin, to: a)
            let large = Geo.offset(from: origin, to: b)
            #expect(abs(large.east - 2 * small.east) < 0.5)
            #expect(abs(large.north - 2 * small.north) < 0.5)
        }
    }

    @Test func initialRadiusMatchesStraightLinePerimeterModel() {
        let shape = shape(seed: 11)
        let radius = shape.initialRadius(target: 6_000, detourFactor: 1.3)
        let ring = [origin] + shape.waypoints(from: origin, radius: radius)
        let perimeter = ring.indices.reduce(0) { $0 + Geo.distance(ring[$1], ring[($1 + 1) % ring.count]) }

        #expect(abs(perimeter * 1.3 - 6_000) / 6_000 < 0.001)
    }

    /// Rastgele parametreler ne olursa olsun kuş uçuşu iskelet kendini kesmez.
    @Test(arguments: 0..<200)
    func skeletonNeverSelfIntersects(seed: UInt64) {
        let ring = [LoopShape.Offset.zero] + shape(seed: seed, bearing: Double(seed) * 17).offsets
        let edges = ring.indices.map { (ring[$0], ring[($0 + 1) % ring.count]) }

        for i in edges.indices {
            for j in edges.indices where j > i + 1 && !(i == 0 && j == edges.count - 1) {
                #expect(!intersects(edges[i], edges[j]), "seed \(seed): edges \(i) and \(j) cross")
            }
        }
    }

    @Test func loopOpensTowardsRequestedBearing() {
        let shape = shape(seed: 3, bearing: 250)
        let pivotBearing = atan2(shape.pivot.east, shape.pivot.north) * 180 / .pi
        #expect(Geo.angularDifference(pivotBearing, 250) < 1e-6)
    }

    @Test func sameSeedSameShapeDifferentSeedDifferentShape() {
        #expect(shape(seed: 42) == shape(seed: 42))
        #expect(shape(seed: 42) != shape(seed: 43))
    }

    @Test func repairPullsWaypointTowardsPivotOnly() {
        let shape = shape(seed: 5)
        let repaired = shape.pullingIn(waypoint: 1, by: 0.6)

        let before = hypot(shape.offsets[1].east - shape.pivot.east, shape.offsets[1].north - shape.pivot.north)
        let after = hypot(repaired.offsets[1].east - shape.pivot.east, repaired.offsets[1].north - shape.pivot.north)
        #expect(abs(after - 0.6 * before) < 1e-9)
        #expect(repaired.offsets[0] == shape.offsets[0])
    }

    /// Küçük kayma eski koordinatı korur (cache isabeti), büyük kayma korumaz.
    @Test func pinningKeepsOnlySmallShifts() {
        let previous = [point(east: 0, north: 500), point(east: 500, north: 500)]
        let proposed = [point(east: 20, north: 510), point(east: 600, north: 500)]
        let pinned = LoopShape.pin(proposed, to: previous, tolerance: 35)

        #expect(pinned[0].latitude == previous[0].latitude && pinned[0].longitude == previous[0].longitude)
        #expect(pinned[1].latitude == proposed[1].latitude && pinned[1].longitude == proposed[1].longitude)
    }

    private func intersects(_ a: (LoopShape.Offset, LoopShape.Offset), _ b: (LoopShape.Offset, LoopShape.Offset)) -> Bool {
        func cross(_ o: LoopShape.Offset, _ p: LoopShape.Offset, _ q: LoopShape.Offset) -> Double {
            (p.east - o.east) * (q.north - o.north) - (p.north - o.north) * (q.east - o.east)
        }
        return cross(b.0, b.1, a.0) * cross(b.0, b.1, a.1) < 0
            && cross(a.0, a.1, b.0) * cross(a.0, a.1, b.1) < 0
    }
}

// MARK: - Yön ve öğrenme

struct BearingAndDetourTests {
    @Test func leastUsedBearingIsOppositeOfSingleUsedBearing() {
        #expect(BearingPlanner.leastUsedBearing(avoiding: [90]) == 270)
        #expect(BearingPlanner.leastUsedBearing(avoiding: []) == nil)
    }

    /// Altın açı adımı: ilk dört deneme çember üzerinde birbirinden en az ~50° uzak.
    @Test func goldenAngleSpreadsAttempts() {
        let bearings = (0..<4).map { BearingPlanner.bearing(forAttempt: $0, base: 10, jitter: 0) }
        for i in bearings.indices {
            for j in bearings.indices where j > i {
                #expect(Geo.angularDifference(bearings[i], bearings[j]) >= 50)
            }
        }
    }

    /// Her bölge (göz) kendi katsayısını öğrenir; uzak bölge varsayılanla başlar.
    @Test func detourEstimateLearnsPerRegion() {
        var estimate = DetourEstimate()
        #expect(estimate.factor(near: origin) == DetourEstimate.initial)

        estimate.observe(1.6, at: origin)
        #expect(estimate.factor(near: origin) == 1.6)

        estimate.observe(1.4, at: origin)
        #expect(abs(estimate.factor(near: origin) - 1.5) < 1e-9)

        #expect(estimate.factor(near: point(east: 10_000, north: 0)) == DetourEstimate.initial)
    }

    /// Bütçe sabit bir sayı değil; planın en kötü maliyetinden türer ve plan
    /// büyüdükçe onunla birlikte büyür.
    @Test func requestBudgetIsDerivedFromPlan() {
        var policy = GenerationPolicy()
        let perEvaluation = policy.vertexCountRange.upperBound + 2
        let recoveries = policy.maxRecoveries + policy.maxThrottleRecoveries
        #expect(policy.loopRequestBudget
                == (policy.maxLoopAttempts * policy.maxEvaluations + recoveries) * perEvaluation)

        let before = policy.loopRequestBudget
        policy.maxLoopAttempts += 1
        #expect(policy.loopRequestBudget == before + policy.maxEvaluations * perEvaluation)

        #expect(policy.backoff(forRecovery: 1) == .seconds(1))
        #expect(policy.backoff(forRecovery: 3) == .seconds(4))
    }
}

// MARK: - Rota izi

struct RouteFootprintTests {
    private let street = path([(0, 0), (1_000, 0)])

    @Test func sameStreetOverlapsFullyParallelStreetDoesNot() {
        let footprint = RouteFootprint(street)
        let oppositeSidewalk = RouteFootprint(path([(0, 12), (1_000, 12)]))
        let parallelStreet = RouteFootprint(path([(0, 100), (1_000, 100)]))

        #expect(footprint.overlap(with: footprint, corridor: 25, excluding: origin, startZone: 0) == 1)
        #expect(oppositeSidewalk.overlap(with: footprint, corridor: 25, excluding: origin, startZone: 0) == 1)
        #expect(parallelStreet.overlap(with: footprint, corridor: 25, excluding: origin, startZone: 0) == 0)
    }

    /// Aynı sokaktan çıkıp farklı yönlere giden iki döngü, başlangıç bölgesi
    /// hariç tutulunca örtüşmez.
    @Test func startZoneIsNotCountedAsSimilarity() {
        let north = RouteFootprint(path([(0, 0), (150, 0), (150, 1_000)]))
        let south = RouteFootprint(path([(0, 0), (150, 0), (150, -1_000)]))

        #expect(north.overlap(with: south, corridor: 25, excluding: origin, startZone: 0) > 0.1)
        #expect(north.overlap(with: south, corridor: 25, excluding: origin, startZone: 200) == 0)
    }

    @Test func detectsDeadEndSpurButNotCleanLoop() {
        let spur = RouteFootprint(path([(0, 0), (400, 0), (0, 0)]))
        let square = RouteFootprint(path([(0, 0), (400, 0), (400, 400), (0, 400), (0, 0)]))

        #expect(spur.longestRepeatedStretch(excluding: origin, startZone: 0) > 150)
        #expect(square.longestRepeatedStretch(excluding: origin, startZone: 0) == 0)
    }
}
