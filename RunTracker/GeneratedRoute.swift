//
//  GeneratedRoute.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 31.08.2026.
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Üretilen rota

/// Kullanıcıya gösterilen tek bir rota.
struct GeneratedRoute: Identifiable {
    enum Kind {
        /// Başladığı yerde biten döngü.
        case loop
        /// Yedek strateji: bir noktaya gidip geri dönüş.
        case outAndBack
    }

    let id = UUID()
    /// Rotanın başladığı ve bittiği nokta.
    let start: CLLocationCoordinate2D
    /// Sırayla uç uca eklenince rotayı oluşturan MapKit yürüme bacakları.
    let legs: [MKRoute]
    /// Toplam uzunluk (metre): bacakların gerçek mesafelerinin toplamı.
    let distance: Double
    /// İstenen mesafe (metre).
    let targetDistance: Double
    let kind: Kind
    /// Rotanın başlangıçtan bakınca açıldığı yön (derece).
    let bearing: Double

    var polylines: [MKPolyline] { legs.map(\.polyline) }
    var distanceInKm: Double { distance / 1000 }
    var distanceMeasurement: Measurement<UnitLength> { Measurement(value: distance, unit: .meters) }
    /// Hedefe bağıl sapma: +0.08 = %8 uzun, −0.05 = %5 kısa.
    var distanceError: Double { (distance - targetDistance) / targetDistance }
}

// MARK: - Hatalar

enum RouteGenerationError: LocalizedError {
    case locationUnavailable
    case invalidDistance
    /// Ne döngü ne git-gel: çevrede yürünebilir yol bulunamadı.
    case noWalkableRoute
    /// MapKit istekleri sınırlıyor ve toparlanma hakları tükendi.
    case rateLimited
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .locationUnavailable: "Waiting for your location…"
        case .invalidDistance: "Enter a distance between 0.5 and 50 km."
        case .noWalkableRoute: "No walkable route found nearby."
        case .rateLimited: "Too many route requests. Try again in a minute."
        case .networkUnavailable: "Can't reach Apple Maps. Check your connection."
        }
    }

    /// Toparlanma hakları biten ağ hatasının kullanıcıya gösterilen karşılığı.
    init(_ failure: DirectionsFailure) {
        switch failure {
        case .throttled: self = .rateLimited
        case .unavailable: self = .networkUnavailable
        }
    }
}
