//
//  WeekTracker.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 18.09.2026.
//

import Foundation
import SwiftUI
import SwiftData

extension Date {
    var isInCurrentWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }
}

class WeekTracker {
    // #Predicate özel hesaplanmış özellikleri (isInCurrentWeek) desteklemediği
    // için hafta sınırları sabit değer olarak yakalanır.
    @Query private var currentWeekSessions: [RunSession]

    init() {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!
        let start = interval.start
        let end = interval.end
        _currentWeekSessions = Query(
            filter: #Predicate<RunSession> { $0.startedAt >= start && $0.startedAt < end },
            sort: \.startedAt
        )
    }
}
