//
//  FavoritePathsSheet.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 22.09.2026.
//

import SwiftUI
import SwiftData
import MapKit

struct FavoritePathsSheet: View {
    @Query(filter: #Predicate<TraveledPath> { $0.isFavorite }) var favPaths: [TraveledPath]
    
    var body: some View {
        Text("Favorite Paths")
            .font(.title2)
            .bold()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        List(favPaths) {path in
            FavRow(path: path)
        }
    }
}

struct FavRow: View {
    var path: TraveledPath
    @State private var cameraPosition: MapCameraPosition = .automatic
    var body: some View {
        HStack{
            VStack(alignment: .leading){
                Text(Measurement(value: path.distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0)))))
                Text("Used \(path.timesUsed) times")
                    .font(.caption)
                    
                NavigationLink(destination: NavigationView(route: path)) {
                    HStack{
                        Image(systemName: "location.north.fill")
                        Text("Start Navigation")
                    }
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.emerald)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            Spacer()
            Map(position: $cameraPosition) {
                ForEach(Array(path.polylines.enumerated()), id: \.offset) { _, polyline in
                    MapPolyline(polyline)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            .mapControlVisibility(.hidden)
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(width: 100, height: 100)
        }
    }
}
