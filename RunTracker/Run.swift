//
//  Run.swift
//  RunTracker
//

import Foundation
import CoreLocation

struct Run: Identifiable {
    let id = UUID()
    let route: [CLLocationCoordinate2D] // koşulan gerçek yol
    let date: Date
    let distance: CLLocationDistance // metre
    let duration: TimeInterval // saniye
}

@Observable
class RunStore {
    var runs: [Run] = []

    func add(_ run: Run) {
        runs.insert(run, at: 0) // en yeni koşu başta
    }
}

/// Saniye cinsinden süreyi "mm:ss" veya "h:mm:ss" olarak biçimler
func formattedDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}
