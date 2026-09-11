//
//  RunSession.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import Foundation
import SwiftUI
import MapKit
import CoreLocation
import SwiftData

// MARK: - Koşu kaydı

/// Tamamlanmış bir koşu: ne kadar sürdüğü, ne kadar yol gidildiği ve
/// kullanıcının gerçekten geçtiği yol.
///
/// Geçilen yol, planlanan rotadan ayrı tutulur: rota nereden gidilmesi
/// gerektiğini, bu kayıt ise gerçekte nereden gidildiğini gösterir.

// RunSession.swift
@Model
final class RunSession {
    var startedAt: Date
    var endedAt: Date
    var segments: [RouteSegment]
    var distance: Double
    var plannedDistance: Double?

    var user: User?
    var traveledPath: TraveledPath?

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var distanceInKm: Double { distance / 1000 }
    var pace: TimeInterval? { distance > 0 ? duration / distanceInKm : nil }

    init(
        startedAt: Date,
        endedAt: Date = .now,
        segments: [[CLLocationCoordinate2D]],
        plannedDistance: Double? = nil,
        traveledPath: TraveledPath? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedDistance = plannedDistance
        self.traveledPath = traveledPath

        let recorded = segments.filter { $0.count > 1 }
        distance = Self.distance(of: recorded)
        self.segments = recorded.map { RouteSegment(points: $0.map(RoutePoint.init)) }
    }

    static func distance(of segments: [[CLLocationCoordinate2D]]) -> Double {
        segments.reduce(0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
        }
    }

    func formatted(seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .time(pattern: seconds < 3600 ? .minuteSecond : .hourMinuteSecond)
        )
    }
}
// MARK: - Harita katmanı

/// Kullanıcının gerçekten geçtiği yol. Planlanan rotadan (mavi) ayırt edilsin
/// diye ayrı renkte ve onun üstünde çizilir.
@Model
final class TraveledPath {
    var name: String
    var segments: [RouteSegment]
    var isFavorite: Bool
    var createdDate: Date

    @Relationship(inverse: \RunSession.traveledPath)
    var sessions: [RunSession] = []

    var timesUsed: Int { sessions.count }
    var totalDistance: Double { sessions.reduce(0) { $0 + $1.distance } }

    init(name: String, segments: [RouteSegment], isFavorite: Bool = false) {
        self.name = name
        self.segments = segments
        self.isFavorite = isFavorite
        self.createdDate = .now
    }
}

/// Bir koşuda gerçekten geçilen yolun haritada çizimi. Persist edilmez,
/// `RunSession.segments`'tan view'da her seferinde türetilir.
struct RunRouteOverlay: MapContent {
    let segments: [[CLLocationCoordinate2D]]
    var tint: Color = .orange

    init(_ session: RunSession, tint: Color = .orange) {
        segments = session.segments.map { $0.points.map(\.coordinate) }
        self.tint = tint
    }

    init(segments: [[CLLocationCoordinate2D]], tint: Color = .orange) {
        self.segments = segments.filter { $0.count > 1 }
        self.tint = tint
    }

    var body: some MapContent {
        ForEach(segments.indices, id: \.self) { index in
            MapPolyline(coordinates: segments[index])
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
    }
}
