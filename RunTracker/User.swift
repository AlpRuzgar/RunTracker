//
//  User.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 9.09.2026.
//

import Foundation
import SwiftData

enum Sex {
    case male
    case female
    case neither
}

struct User {
    var email: String
    var name: String
    var sex: Sex
    var bday: Date
    var sessions: [RunSession] = []
    var sessionCount: Int { sessions.count }
    var totalDistance: Double { sessions.reduce(0) { $0 + $1.distance } }
}
