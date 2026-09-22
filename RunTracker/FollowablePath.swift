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
    /// Yolun başladığı nokta. Kayıtlı yollarda ilk konum boş olabilir
    /// (ör. GPS sabitlenmeden bitirilen bir koşu) — `nil` bunu yansıtır.
    var startCoordinate: CLLocationCoordinate2D? { get }
    /// Toplam uzunluk (metre).
    var distance: Double { get }
}

extension FollowablePath {
    /// Yolun başladığı yerin ilçe/semt adı. Başlangıç noktası bilinmiyorsa
    /// (ör. hiç konum kaydedilmeden bitirilen bir serbest koşu) hata fırlatır.
    @MainActor
    var district: String {
        get async throws {
            guard let coordinate = startCoordinate else {
                throw NSError(domain: "FollowablePath", code: 0, userInfo: [NSLocalizedDescriptionKey: "Başlangıç konumu yok"])
            }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return try await location.getCityDistrict()
        }
    }
}

extension GeneratedRoute: FollowablePath {
    /// Döngü başladığı yerde biter.
    var destination: CLLocationCoordinate2D? { start }
    var startCoordinate: CLLocationCoordinate2D? { start }
}

extension TraveledPath: FollowablePath {
    var polylines: [MKPolyline] { segments.polylines }

    /// Kayıtlı yolun MapKit talimatları yoktur.
    var legs: [MKRoute] { [] }

    var destination: CLLocationCoordinate2D? {
        segments.last?.points.last?.coordinate
    }

    var startCoordinate: CLLocationCoordinate2D? {
        segments.first?.points.first?.coordinate
    }

    var distance: Double {
        RunSession.distance(of: segments.map { $0.points.map(\.coordinate) })
    }
}

// MARK: - Ters yön

/// Bir yolun ters yönde takip edilen hâli: aynı çizgiler, ters sırada.
///
/// Talimat taşımaz. `MKRoute`'un adımları yönlüdür ("200 m sonra sağa dönün");
/// çizgi gibi ters çevrilemezler. Ters yön için MapKit'e yeniden sorulabilirdi
/// ama iki bedeli var: bacak başına bir istek (bkz. `RouteGenerator`'ın kota
/// hassasiyeti) ve MapKit'in ters yönde BAŞKA sokaklar önerebilmesi — o zaman
/// sonuç "aynı rotanın tersi" olmaktan çıkardı. Bu yüzden ters yön, kaydedilmiş
/// yollar gibi talimatsız takip edilir; gidiş yönünü rotadaki oklar taşır.
struct ReversedPath: FollowablePath {
    let polylines: [MKPolyline]
    let destination: CLLocationCoordinate2D?
    /// Ters yönün başlangıcı, ileri yöndeki BİTİŞ noktasıdır.
    let startCoordinate: CLLocationCoordinate2D?
    let distance: Double

    /// Talimatlar ters çevrilemediği için ters yönde bacak yoktur.
    var legs: [MKRoute] { [] }
}

extension FollowablePath {
    /// Aynı yolun ters yönde takip edilen hâli.
    ///
    /// Parçalar hem kendi içinde hem de aralarında ters çevrilir; tek bir çizgide
    /// birleştirilmez, yoksa duraklamayla bölünmüş kayıtlı yollarda boşluğun iki
    /// ucu düz bir çizgiyle bağlanmış gibi görünürdü.
    ///
    /// Bitiş, yolun ileri yöndeki BAŞLANGIÇ noktasıdır; döngülerde ikisi zaten
    /// aynı yerdir.
    func reversed() -> ReversedPath {
        ReversedPath(
            polylines: polylines.reversed().map { polyline in
                let coordinates = Array(Geo.coordinates(of: polyline).reversed())
                return MKPolyline(coordinates: coordinates, count: coordinates.count)
            },
            destination: polylines.first.flatMap(Geo.firstCoordinate),
            startCoordinate: destination,
            distance: distance
        )
    }
}
