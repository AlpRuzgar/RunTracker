//
//  ChartView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 16.09.2026.
//

import SwiftUI
import Charts

/// Haftalık sütun grafiği. Eksen süsleri elden geçirildi: ızgara çizgileri ve
/// çerçeve kaldırıldı, geriye yalnızca sütunlar ve gün adları kaldı — kartın
/// içinde bir grafik değil, bir ritim gibi okunsun.
struct WeeklyChartView: View {
    var type: String = "Distance"
    var data: [Double]
    var days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var tint: Color = .secondaryGreen

    var body: some View {
        Chart(days.indices, id: \.self) { index in
            BarMark(
                x: .value("Day", days[index]),
                y: .value(type, index < data.count ? data[index] : 0),
                width: .ratio(0.5)
            )
            .foregroundStyle(tint)
            .cornerRadius(6)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 150)
    }
}

#Preview {
    WeeklyChartView(data: [10, 5, 20, 0, 30, 15, 25])
        .card()
        .padding()
        .background(Color.canvas)
}
