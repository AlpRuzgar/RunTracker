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
@Model
final class RunSession {
    var startedAt: Date
    var endedAt: Date
    var segments: [RouteSegment]
    var distance: Double
    var plannedDistance: Double?

    var traveledPath: TraveledPath?

    /// Koşuyu yapan kullanıcı; ters ilişki `User.sessions` üzerinde tanımlı.
    var user: User?

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var distanceInKm: Double { distance / 1000 }
    var distanceMeasurement: Measurement<UnitLength> {
        Measurement(value: distance, unit: .meters)
    }
    var pace: TimeInterval? { distance > 0 ? duration / distanceInKm : nil }
    /// Koşunun başladığı yerin ilçe/semt adı. Rota üzerinden gidilen koşularda
    /// da serbest koşularda da kaynak `traveledPath`'tir (`FollowablePath`);
    /// başlangıç konumu hiç kaydedilmediyse (ör. GPS sabitlenmeden bitirilen
    /// bir serbest koşu) hata fırlatır.
    @MainActor
    var district: String {
        get async throws {
            guard let coordinate = traveledPath?.startCoordinate else {
                throw NSError(domain: "RunSession", code: 0, userInfo: [NSLocalizedDescriptionKey: "Kaydedilmiş yol yok"])
            }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return try await location.getCityDistrict()
        }
    }

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

    /// Parçaların toplam uzunluğu (metre). Parçalar arası boşluk (duraklama)
    /// sayılmaz.
    static func distance(of segments: [[CLLocationCoordinate2D]]) -> Double {
        segments.reduce(0) { $0 + Geo.length(of: $1) }
    }
}

extension RunSession {
    /// Biten bir koşuyu ve geçilen yolu (yeniden koşulabilsin diye yeni bir
    /// `TraveledPath` olarak) kaydeder. İki koşu ekranı da bunu kullanır.
    ///
    /// Kayıt hemen diske yazılır: kilit ekranından bitirilen koşuda uygulama
    /// arka plandadır ve otomatik kaydı beklemeden askıya alınabilir.
    static func saveFinishedRun(
        startedAt: Date,
        endedAt: Date = .now,
        segments: [[CLLocationCoordinate2D]],
        plannedDistance: Double? = nil,
        pathName: String,
        user: User?,
        in context: ModelContext
    ) {
        let session = RunSession(startedAt: startedAt, endedAt: endedAt, segments: segments, plannedDistance: plannedDistance)
        session.traveledPath = TraveledPath(
            name: "\(pathName) — \(startedAt.formatted(date: .abbreviated, time: .shortened))",
            segments: session.segments
        )
        session.user = user
        context.insert(session)
        try? context.save()
    }
}

extension RunSession {
    static func currentWeekPredicate() -> Predicate<RunSession> {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!
        let start = interval.start
        let end = interval.end
        return #Predicate<RunSession> { $0.startedAt >= start && $0.startedAt < end }
    }
}

// MARK: - Kayıtlı yol

/// Kullanıcının gerçekten geçtiği, yeniden koşulabilen (bkz. `FollowablePath`)
/// ve favorilere eklenebilen yol.
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

// MARK: - Harita katmanı

/// Bir koşuda gerçekten geçilen yolun haritada çizimi. Persist edilmez, koşu
/// ekranında canlı olarak çizilir; planlanan rotanın (`RouteOverlay`) üstünde
/// ayrı renkte durur.
struct RunRouteOverlay: MapContent {
    let segments: [[CLLocationCoordinate2D]]
    var tint: Color = .orange

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
