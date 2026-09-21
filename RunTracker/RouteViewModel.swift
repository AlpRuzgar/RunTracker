//
//  RouteViewModel.swift
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
}

// MARK: - Durum

/// Rota ekranının tüm durumu tek bir enum'da. "Hata var ama yükleniyor" ya da
/// "rota hazır ama hata bayrağı açık" gibi çelişkili kombinasyonlar, ayrı
/// boolean/optional'larla mümkünken burada temsil bile edilemez.
enum RouteGenerationState {
    case idle
    /// Üretim sürüyor; varsa önceki rota bu sırada haritada kalır.
    case generating(previous: GeneratedRoute?)
    case ready(GeneratedRoute)
    case failed(RouteGenerationError)
}

// MARK: - View model

/// Rota ekranının view model'i: üretim görevini yönetir ve sonucu tek bir
/// `state` üzerinden yayınlar. Üretimin kendisi `RouteGenerator`'dadır.
///
/// Uygulamada TEK bir örneği vardır (`RunTrackerApp` environment'a koyar).
/// Sekmelerin kendi kopyasını yaratması üç şeyi birden bozuyordu: her kopya
/// MapKit'in hız kotasını kendi başına harcıyordu (ikisi birlikte kotayı aşıp
/// throttle yiyordu), bacak cache'i bölünüyordu ve "son rotalar" geçmişi ayrı
/// olduğu için iki sekme birbirinin rotasının aynısını üretebiliyordu.
@Observable
final class RouteViewModel {
    /// Kabul edilen hedef mesafe aralığı (metre).
    static let distanceRange = 500.0...50_000.0
    /// Başarılı üretimden sonra yeni üretime izin verilmeyen süre (saniye).
    /// Kotayı `RequestPacer` koruduğu için bunun tek işi kazara çift dokunmayı
    /// engellemek; art arda üretimler serbesttir, sadece pacer yüzünden biraz
    /// daha yavaş başlar.
    private static let successCooldown = 2
    /// MapKit throttle penceresi tipik olarak ~1 dk sürer; hata sonrası bekleme.
    private static let rateLimitCooldown = 60

    private(set) var state: RouteGenerationState = .idle
    /// Yeni üretime izin verilene kadar kalan saniye (0 = beklemiyor).
    private(set) var cooldownRemaining = 0
    /// Süren üretimin ilerlemesi; üretim yokken `nil`.
    private(set) var progress: GenerationProgress?

    private let generator: RouteGenerator
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?

    init(generator: RouteGenerator = RouteGenerator(store: UserDefaults.standard)) {
        self.generator = generator
    }

    /// Haritada gösterilecek rota: hazırsa o, üretim sürüyorsa bir önceki.
    var route: GeneratedRoute? {
        switch state {
        case .ready(let route): route
        case .generating(let previous): previous
        case .idle, .failed: nil
        }
    }

    var isGenerating: Bool {
        if case .generating = state { true } else { false }
    }

    /// Süren üretimin tek satırlık özeti; boş bir spinner yerine nerede
    /// olunduğunu gösterir.
    var progressDescription: String? {
        guard let progress else { return nil }
        let phase = progress.isFallback ? "Straight route" : "Route"
        return "\(phase) \(progress.attempt)/\(progress.maxAttempts)…"
    }

    func generate(from start: CLLocationCoordinate2D?, targetKilometers: Double) {
        guard cooldownRemaining == 0 else { return }
        guard let start else {
            state = .failed(.locationUnavailable)
            return
        }
        let target = targetKilometers * 1000
        guard Self.distanceRange.contains(target) else {
            state = .failed(.invalidDistance)
            return
        }

        // Yeni istek eskisini geçersiz kılar. İptal edilen görev durumu değiştirmez:
        // durum artık yeni isteğe ait.
        task?.cancel()
        state = .generating(previous: route)
        progress = nil
        task = Task {
            defer { progress = nil }
            do {
                let route = try await generator.generate(from: start, targetDistance: target) { [weak self] step in
                    guard let self, !Task.isCancelled else { return }
                    progress = step
                }
                guard !Task.isCancelled else { return }
                state = .ready(route)
                beginCooldown(seconds: Self.successCooldown)
            } catch {
                guard !Task.isCancelled else { return }
                let failure = error as? RouteGenerationError ?? .networkUnavailable
                state = .failed(failure)
                if case .rateLimited = failure {
                    beginCooldown(seconds: Self.rateLimitCooldown)
                }
            }
        }
    }

    /// Elde gösterilecek bir rota yoksa üretir. Ana ekranın "Quick Route" kartı
    /// bunu kullanır: açılışta zaten bir rota varsa (ör. kullanıcı Run sekmesinde
    /// üretmiş) ağa hiç gidilmez. Eskiden ana ekran her açılışta kendi motoruyla
    /// baştan üretiyor, hem MapKit kotasını hem de patlama kredisini kullanıcının
    /// asıl isteyeceği üretimden önce harcıyordu.
    func generateIfNeeded(from start: CLLocationCoordinate2D?, targetKilometers: Double) {
        guard route == nil, !isGenerating else { return }
        generate(from: start, targetKilometers: targetKilometers)
    }

    /// Üretim düğmesini `seconds` boyunca kilitler ve kalan süreyi saniyede bir
    /// günceller; UI geri sayımı `cooldownRemaining` üzerinden gösterir.
    private func beginCooldown(seconds: Int) {
        cooldownTask?.cancel()
        cooldownRemaining = seconds
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                cooldownRemaining -= 1
                if cooldownRemaining <= 0 { return }
            }
        }
    }
}
