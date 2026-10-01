//
//  GenerationStore.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 15.09.2026.
//

import Foundation

// MARK: - Kalıcı bellek

/// Üretimin oturumlar arasında hatırladıkları.
///
/// İkisi de aynı amaca hizmet eder: uygulama yeniden açıldığında üretim sıfırdan
/// başlamasın. Dolambaç katsayısı ilk yarıçap tahminini tutturur (hız); rota
/// geçmişi yeni rotanın eskilerden farklı bir yöne açılmasını sağlar (çeşitlilik).
/// Eskiden yalnızca ilki saklanıyordu, bu yüzden her açılışta ilk rota önceki
/// oturumunkinin kopyası olabiliyordu.
protocol GenerationStoring {
    func loadDetourFactors() -> [String: Double]
    func saveDetourFactors(_ factors: [String: Double])
    func loadRouteHistory() -> [RouteHistoryEntry]
    func saveRouteHistory(_ history: [RouteHistoryEntry])
}

/// Hatırlanan bir rotanın saklanan hâli: nereden, hangi yöne açıldığı ve izinin
/// seyreltilmiş örnekleri.
nonisolated struct RouteHistoryEntry: Codable {
    var start: RoutePoint
    var bearing: Double
    var samples: [RoutePoint]
}

extension UserDefaults: GenerationStoring {
    private static let detourFactorsKey = "learnedDetourFactors"
    private static let routeHistoryKey = "recentRoutes"
    /// Rota geçmişinin eski, elle paketlenmiş `[[Double]]` biçimi. Okunmaz:
    /// geçmiş yalnızca çeşitlilik içindir, kaybı zararsızdır. Yalnızca silinir.
    private static let legacyRouteHistoryKey = "recentRouteFootprints"

    func loadDetourFactors() -> [String: Double] {
        dictionary(forKey: Self.detourFactorsKey) as? [String: Double] ?? [:]
    }

    func saveDetourFactors(_ factors: [String: Double]) {
        set(factors, forKey: Self.detourFactorsKey)
    }

    func loadRouteHistory() -> [RouteHistoryEntry] {
        guard let data = data(forKey: Self.routeHistoryKey) else { return [] }
        return (try? JSONDecoder().decode([RouteHistoryEntry].self, from: data)) ?? []
    }

    func saveRouteHistory(_ history: [RouteHistoryEntry]) {
        set(try? JSONEncoder().encode(history), forKey: Self.routeHistoryKey)
        removeObject(forKey: Self.legacyRouteHistoryKey)
    }
}
