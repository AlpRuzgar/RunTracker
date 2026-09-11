//
//  RunCamera.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit
import CoreLocation

/// Koşu ekranlarının kamerası: haritayı kullanıcının üstünde, gittiği yöne
/// dönük ve 3B eğimli tutar — araç navigasyonlarındaki gibi, ekranda yukarı
/// doğru olan yön hep kullanıcının ilerlediği yöndür.
@MainActor
@Observable
final class RunCamera {
    /// Varsayılan eğim (derece): harita düz değil, 3B görünür.
    static let defaultPitch = 60.0
    /// Kameranın kullanıcıya uzaklığı (metre). Koşu hızında birkaç sokak
    /// ileriyi görmek gerekir; araç navigasyonlarından biraz daha geniştir.
    static let defaultDistance = 500.0

    /// Haritanın bağlandığı konum. Kullanıcı haritayı kaydırdığında burayı
    /// harita da değiştirir; takip açıkken bir sonraki konumda geri alınır.
    var position: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Kamera kullanıcıyı takip ediyor mu? Kullanıcı haritayı serbestçe
    /// incelemek isterse kapatılır.
    var isFollowing = true

    var pitch = defaultPitch
    var distance = defaultDistance

    /// Son bilinen gidiş yönü. Kullanıcı durunca yön ölçümü kaybolur; harita
    /// o anda kuzeye dönmesin diye en son yön korunur.
    private(set) var heading = 0.0

    /// Yeni konum ya da yön geldiğinde çağrılır.
    func follow(location: CLLocation?, heading newHeading: Double?) {
        if let newHeading { heading = newHeading }
        guard isFollowing, let location else { return }

        withAnimation(.easeOut(duration: 0.4)) {
            position = .camera(MapCamera(
                centerCoordinate: location.coordinate,
                distance: distance,
                heading: heading,
                pitch: pitch
            ))
        }
    }
}
