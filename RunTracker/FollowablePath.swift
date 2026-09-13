//
//  FollowablePath.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 11.09.2026.
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Takip edilebilir yol

/// Navigasyonun takip edebileceği herhangi bir yol: üretilmiş bir döngü rotası
/// ya da daha önce koşulup kaydedilmiş bir yol. `NavigationViewModel` yalnızca
/// bu protokolü tanır; yolun nereden geldiğini bilmez.
protocol FollowablePath {
    /// Sırayla uç uca takip edilecek çizgiler.
    var polylines: [MKPolyline] { get }
    /// Adım adım talimat taşıyan MapKit bacakları. Kayıtlı yollarda boştur;
    /// o zaman talimatsız düz takip yapılır.
    var legs: [MKRoute] { get }
    /// Varış noktası — döngü rotalarda başlangıçla aynıdır.
    var destination: CLLocationCoordinate2D? { get }
    /// Toplam uzunluk (metre).
    var distance: Double { get }
}

extension GeneratedRoute: FollowablePath {
    /// Döngü başladığı yerde biter.
    var destination: CLLocationCoordinate2D? { start }
}

extension TraveledPath: FollowablePath {
    var polylines: [MKPolyline] {
        segments.map { segment in
            let coordinates = segment.points.map(\.coordinate)
            return MKPolyline(coordinates: coordinates, count: coordinates.count)
        }
    }

    /// Kayıtlı yolun MapKit talimatları yoktur.
    var legs: [MKRoute] { [] }

    var destination: CLLocationCoordinate2D? {
        segments.last?.points.last?.coordinate
    }

    var distance: Double {
        RunSession.distance(of: segments.map { $0.points.map(\.coordinate) })
    }
}
