//
//  User.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 9.09.2026.
//

import Foundation
import SwiftData

enum Sex: String, Codable, CaseIterable {
    case male
    case female
    case neither
}

/// Kullanıcının koşma nedeni; onboarding anketinde seçilir.
enum Motivation: String, Codable, CaseIterable {
    case fatLoss
    case condition
    case racePrep
    case hobby
}

enum Avatar: String, Codable, CaseIterable {
    case rabbit
    case bear
    case fox
    
    var name: String {
        switch self {
        case .rabbit:
            "Snow rabbit"
        case .bear:
            "Brown bear"
        case .fox:
            "Fox"
        }
    }
    var image: String {
        switch self {
        case .rabbit:
            "rabbit"
        case .bear:
            "bear"
        case .fox:
            "fox"
        }
    }

    static func random() -> Avatar {
        return allCases.randomElement()!
    }

}

/// Onboarding anketi tamamlanınca oluşturulan kullanıcı profili.
/// Koşu kayıtları bu profile bağlanır.
@Model
final class User {
    var name: String
    var sex: Sex
    var bday: Date
    var heightCM: Double
    var weightKG: Double
    /// Hedeflenen koşu mesafesi (km).
    var targetDistance: Double
    var motivation: Motivation
    /// Kullanıcının onboarding anketini tamamladığı tarih.
    var createdAt: Date
    var weeklyTarget: Measurement<UnitLength> {
        switch motivation {
        case .hobby: return Measurement(value: 10, unit: .kilometers)
        case .fatLoss: return Measurement(value: 15, unit: .kilometers)
        case .condition: return Measurement(value: 20, unit: .kilometers)
        case .racePrep: return Measurement(value: 25, unit: .kilometers)
        }
    }

    @Relationship(inverse: \RunSession.user)
    var sessions: [RunSession] = []

    var sessionCount: Int { sessions.count }
    var totalDistance: Double { sessions.reduce(0) { $0 + $1.distance } }
    
    var avatar: Avatar = Avatar.random()

    init(
        name: String,
        sex: Sex,
        bday: Date,
        heightCM: Double,
        weightKG: Double,
        targetDistance: Double,
        motivation: Motivation,
        createdAt: Date = .now,
    ) {
        self.name = name
        self.sex = sex
        self.bday = bday
        self.heightCM = heightCM
        self.weightKG = weightKG
        self.targetDistance = targetDistance
        self.motivation = motivation
        self.createdAt = createdAt
    }
}
