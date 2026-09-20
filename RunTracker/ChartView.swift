//
//  ChartView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 16.09.2026.
//

import SwiftUI
import Charts

struct WeeklyChartView: View {
    var type: String = "steps"
    var data: [Double]
    var days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Str", "Sun"]
    var body: some View {
        Chart(days.indices, id: \.self) { i in
            BarMark(x: .value("Day", days[i]), y: .value(type, i < data.count ? data[i] : 0))
        }
        .padding()
    }
}

#Preview {
    WeeklyChartView(data: [10,5,20,0,30,15,25])
}
