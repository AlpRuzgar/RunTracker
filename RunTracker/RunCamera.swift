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

    /// Takip ederken yön bu kadar (derece) değişmedikçe harita döndürülmez.
    /// Dururken pusula birkaç derece oynar ve her oynamada dönen harita
    /// sallanıyordu. Kademeli dönüşler kaybolmaz: fark birikip eşiği aşınca
    /// harita yetişir.
    static let headingThreshold = 12.0
    /// Kameranın bir konumdan sıradakine kayma süresi. Konum saniyede bir
    /// gelir; kayma da o kadar sürünce kamera durmadan akar. Eskiden 0.4 sn'lik
    /// bir yavaşlayan animasyon vardı: kamera sıçrıyor, duruyor, bekliyordu.
    static let glideDuration = 1.0

    /// Haritanın bağlandığı konum. Kullanıcı haritayı kaydırdığında burayı
    /// harita da değiştirir (bkz. `userMovedMap`).
    var position: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Kamera kullanıcıyı takip ediyor mu? Kullanıcı haritayı elle oynatınca
    /// kapanır, takip düğmesiyle geri açılır.
    private(set) var isFollowing = true

    var pitch = defaultPitch
    var distance = defaultDistance

    /// Son bilinen gidiş yönü. Kullanıcı durunca yön ölçümü kaybolur; harita
    /// o anda kuzeye dönmesin diye en son yön korunur.
    private(set) var heading = 0.0
    /// Son bilinen konum: takip yeniden açılınca kamera bir sonraki konumu
    /// beklemeden kullanıcıya döner.
    private var lastLocation: CLLocation?

    /// Yeni konum ya da yön geldiğinde çağrılır. Kamera yalnızca kullanıcı
    /// yer değiştirdiyse ya da yön eşiği aşıldıysa oynar.
    func follow(location: CLLocation?, heading newHeading: Double?) {
        let turned = newHeading.map { Geo.angularDifference($0, heading) >= Self.headingThreshold } ?? false
        if turned, let newHeading { heading = newHeading }
        let moved = location != nil && location !== lastLocation
        if let location { lastLocation = location }

        guard isFollowing, turned || moved else { return }
        moveToUser()
    }

    /// Kullanıcı haritayı elle kaydırdı, yakınlaştırdı ya da döndürdü: takip
    /// kapanır. Eskiden takip açık kaldığı için her konum güncellemesi haritayı
    /// saniyesinde kullanıcıya geri çekiyor, harita incelenemiyordu.
    func userMovedMap() {
        isFollowing = false
    }

    /// Takibi açar ya da kapatır. Açılınca kamera hemen kullanıcıya, varsayılan
    /// eğim ve uzaklığa döner.
    func toggleFollowing() {
        isFollowing.toggle()
        guard isFollowing else { return }
        pitch = Self.defaultPitch
        distance = Self.defaultDistance
        moveToUser()
    }

    private func moveToUser() {
        guard let lastLocation else { return }
        withAnimation(.linear(duration: Self.glideDuration)) {
            position = .camera(MapCamera(
                centerCoordinate: lastLocation.coordinate,
                distance: distance,
                heading: heading,
                pitch: pitch
            ))
        }
    }
}
