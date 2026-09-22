//
//  RouteArrow.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Yön oku

/// Rota üzerinde tek bir yön oku: nereye çizileceği ve rotanın orada hangi
/// yöne gittiği. Döngü rotalarında çizginin kendisi hangi yöne koşulacağını
/// göstermediği için oklar bu bilgiyi taşır.
struct RouteArrow: Identifiable, Equatable {
    /// Rota boyunca sıra numarası. Kimlik rastgele (UUID) olsaydı oklar her
    /// hesaplandığında yepyeni sayılır, harita da kamera her oynadığında bütün
    /// okları söküp yeniden kurardı.
    let id: Int
    let coordinate: CLLocationCoordinate2D
    /// Gidiş yönü (0–360 derece, kuzeyden saat yönünde).
    let heading: Double

    static func == (lhs: RouteArrow, rhs: RouteArrow) -> Bool {
        lhs.id == rhs.id
            && lhs.heading == rhs.heading
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

extension RouteArrow {

    /// Rotayı fazla kalabalıklaştırmadan yönü izlenebilir kılan ok sayısı.
    private static let preferredCount = 14.0
    /// Liste küçük resimlerinde rotanın tamamı birkaç santimetreye sığar;
    /// standart sıklıkta oklar birbirinin üstüne biner.
    private static let compactCount = 3.0
    private static let minimumSpacing = 120.0
    private static let maximumSpacing = 400.0
    /// Okun yönü, çizginin bu yarıçaptaki iki noktası arasından okunur; tek bir
    /// kısa parçanın açısı kaldırım kıvrımlarıyla oynadığı için yanıltıcı olur.
    private static let headingSpan = 10.0

    /// Verilen çizgiler boyunca yaklaşık eşit aralıklı yön okları üretir.
    /// `spacing` verilmezse rotanın uzunluğuna göre seçilir.
    static func along(_ polylines: [MKPolyline], spacing: Double? = nil) -> [RouteArrow] {
        let path = MeasuredPath(Geo.joinedCoordinates(of: polylines))
        guard path.length > 0 else { return [] }

        let step = spacing ?? min(max(path.length / preferredCount, minimumSpacing), maximumSpacing)

        // İlk ok yarım aralık ileride: başlangıç noktasındaki işaretle çakışmaz.
        return stride(from: step / 2, to: path.length, by: step).enumerated().map { index, travelled in
            RouteArrow(
                id: index,
                coordinate: path.coordinate(at: travelled),
                heading: Geo.bearing(
                    from: path.coordinate(at: travelled - headingSpan),
                    to: path.coordinate(at: travelled + headingSpan)
                )
            )
        }
    }

    /// Küçük haritalar için seyrek ok dizisi. Aralık doğrudan rotanın boyundan
    /// hesaplanır; `along`ın alt/üst sınırları burada uygulanmaz, yoksa uzun bir
    /// rota küçük resimde yine on küsur okla dolardı.
    static func sparse(along polylines: [MKPolyline]) -> [RouteArrow] {
        let length = MeasuredPath(Geo.joinedCoordinates(of: polylines)).length
        guard length > 0 else { return [] }
        return along(polylines, spacing: length / compactCount)
    }
}

// MARK: - Mesafeye göre okunabilen çizgi

/// Koordinat dizisini "başından şu kadar metre ileride hangi nokta var?"
/// sorusuna cevap verebilecek şekilde saklar.
private struct MeasuredPath {
    private let coordinates: [CLLocationCoordinate2D]
    /// `travelled[i]`, dizinin başından `coordinates[i]`ye yürünen mesafe.
    private let travelled: [Double]

    var length: Double { travelled.last ?? 0 }

    init(_ coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates

        var total = 0.0
        var distances = coordinates.isEmpty ? [] : [0.0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            total += Geo.distance(a, b)
            distances.append(total)
        }
        self.travelled = distances
    }

    /// Çizginin başından `distance` metre ileride kalan nokta; dışarıda kalan
    /// mesafeler uçlara kırpılır.
    func coordinate(at distance: Double) -> CLLocationCoordinate2D {
        guard let first = coordinates.first, let last = coordinates.last else {
            return CLLocationCoordinate2D()
        }
        guard distance > 0 else { return first }
        guard distance < length else { return last }

        guard let next = travelled.firstIndex(where: { $0 >= distance }), next > 0 else { return first }
        let segment = travelled[next] - travelled[next - 1]
        let fraction = segment > 0 ? (distance - travelled[next - 1]) / segment : 0

        return Geo.interpolate(from: coordinates[next - 1], to: coordinates[next], fraction: fraction)
    }
}

// MARK: - Rota katmanı

/// Bir rotanın haritadaki tam gösterimi: çizgisi ve gidiş yönü okları.
///
/// İkisi tek katmanda toplanmıştır çünkü rota çizgisi tek başına eksik bilgidir:
/// döngü rotasında çizgi hangi yöne koşulacağını göstermez, ters yönde takip
/// edilen rotada ise çizgi ileri yöndekiyle birebir aynıdır. Rota nereye
/// çizilirse çizilsin okların da çizilmesi için tek giriş noktası budur.
struct RouteOverlay: MapContent {

    /// Ok sıklığı: tam ekran harita ile liste küçük resmi aynı sıklığı kaldırmaz.
    enum Density {
        case standard
        /// Küçük resim (bkz. `RouteArrow.sparse`).
        case compact
    }

    let polylines: [MKPolyline]
    /// Rota rengi emerald: uygulamanın "ilerleme" rengi (bkz. `Theme.swift`).
    /// Önizlemede, navigasyonda ve küçük resimlerde aynı renk kullanılır ki
    /// kullanıcı her yerde aynı şeye baktığını bilsin.
    var tint: Color = .emerald
    /// Haritanın kuzeye göre dönüklüğü; `onMapCameraChange`'den gelir.
    /// Döndürülemeyen küçük resim haritalarında 0 kalır.
    var mapHeading: Double = 0
    var density: Density = .standard
    /// Hazır ok dizisi. Kamerası sürekli oynayan haritalarda (navigasyon, ana
    /// harita) oklar bir kez hesaplanıp buradan verilir: aksi hâlde her karede
    /// rotanın tamamı yeniden ölçülürdü. Küçük resimler nadiren çizildiği için
    /// `nil` geçip hesabı buraya bırakabilir.
    var arrows: [RouteArrow]?

    var body: some MapContent {
        // Kimlik sıraya bağlanır: `polylines` çoğu yerde her okumada yeni
        // `MKPolyline` nesneleri üreten hesaplanmış bir özelliktir, nesne
        // kimliğiyle her çizimde hepsi değişmiş sayılırdı.
        ForEach(Array(polylines.enumerated()), id: \.offset) { _, polyline in
            MapPolyline(polyline)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }

        RouteDirectionArrows(
            arrows: arrows ?? computedArrows,
            mapHeading: mapHeading,
            tint: tint
        )
    }

    private var computedArrows: [RouteArrow] {
        switch density {
        case .standard: RouteArrow.along(polylines)
        case .compact: RouteArrow.sparse(along: polylines)
        }
    }
}

// MARK: - Çerçeveleme

extension Array where Element == MKPolyline {
    /// Çizgilerin tamamını kenar payıyla içine alan harita bölgesi.
    ///
    /// Küçük resimlerde `.automatic` kullanılmaz: kısa bir yolu (birkaç yüz
    /// metre) çok geniş bir alanın ortasına yerleştirip yolu görünmez hâle
    /// getiriyordu.
    func framingRect(padding: Double = 0.35) -> MKMapRect {
        let rect = reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        guard !rect.isNull else { return MKMapRect.world }
        // Çok kısa yollarda oran tabanlı pay sıfıra yaklaşır; en az bir taban
        // pay eklenir ki tek noktalık kayıtlarda bile makul bir alan kalsın.
        let dx = Swift.max(rect.width * padding, 200)
        let dy = Swift.max(rect.height * padding, 200)
        return rect.insetBy(dx: -dx, dy: -dy)
    }
}

// MARK: - Harita katmanı

/// Yön oklarını haritaya yerleştirir.
///
/// Ok simgeleri harita değil ekran ile hizalı çizildiği için, harita
/// döndürüldüğünde (pusula modu, 3B eğim) oklar aynı miktarda geri döndürülür;
/// böylece hep gerçek gidiş yönünü gösterirler.
struct RouteDirectionArrows: MapContent {
    let arrows: [RouteArrow]
    /// Haritanın kuzeye göre dönüklüğü (derece) — `onMapCameraChange`'den gelir.
    var mapHeading: Double = 0
    var tint: Color = .emerald

    var body: some MapContent {
        ForEach(arrows) { arrow in
            Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(tint.gradient, in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                    .rotationEffect(.degrees(arrow.heading - mapHeading))
                    .shadow(radius: 1)
            }
            .annotationTitles(.hidden)
        }
    }
}
