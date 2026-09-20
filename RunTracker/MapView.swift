//
//  MapView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit

struct MapView: View {
    @State private var routes = RouteViewModel()
    @State private var locationManager = LocationManager()
    @State private var distance: Double = 0.0
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @FocusState private var isDistanceFocused: Bool

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                if let route = routes.route {
                    ForEach(route.polylines, id: \.self) { polyline in
                        MapPolyline(polyline)
                            .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            // simultaneousGesture: klavyeyi kapatırken haritanın kendi
            // dokunma etkileşimlerini engellememek için.
            .simultaneousGesture(TapGesture().onEnded {
                isDistanceFocused = false
            })
            .mapControls {
                MapUserLocationButton()
                MapScaleView()
            }
            .overlay(alignment: .bottom) {
                controlPanel
                    .padding()
            }
            // Yeni rota gelince kamera onu tamamen gösterecek şekilde kayar.
            // Üretim sürerken gösterilen önceki rotanın kimliği değişmez.
            .onChange(of: routes.route?.id) {
                guard case .ready(let route) = routes.state else { return }
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .rect(boundingRect(of: route))
                }
            }
        }
    }

    /// Haritanın üzerinde yüzen kontrol paneli. Ayrı cam parçaları tek
    /// `GlassEffectContainer` içinde toplanır ki beliren/kaybolan parçalar
    /// birbirine karışarak (morph) geçiş yapsın.
    private var controlPanel: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 12) {
                if let route = routes.route {
                    routeCard(route)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .glassEffect()
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                distanceField

                HStack(spacing: 12) {
                    NavigationLink {
                        FreeRunView()
                    } label: {
                        ButtonView(text: "Free Run", symbol: "figure.run")
                    }
                    .buttonStyle(.glass)
                    .simultaneousGesture(TapGesture().onEnded {
                        isDistanceFocused = false
                    })

                    Button {
                        isDistanceFocused = false
                        routes.generate(from: locationManager.userLocationCoordinate2D, targetKilometers: distance)
                    } label: {
                        ButtonView(
                            text: generateButtonText,
                            symbol: routes.cooldownRemaining > 0 ? "hourglass" : "sparkles",
                            isLoading: routes.isGenerating
                        )
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
                    .disabled(distance <= 0 || routes.isGenerating || routes.cooldownRemaining > 0)
                }

                // Rota hazır olunca navigasyonlu koşu başlatılabilir.
                if case .ready(let route) = routes.state {
                    NavigationLink {
                        NavigationView(route: route)
                    } label: {
                        ButtonView(text: "Start Navigation", symbol: "location.north.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
                    .simultaneousGesture(TapGesture().onEnded {
                        isDistanceFocused = false
                    })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.25), value: routes.route?.id)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: errorMessage)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: routes.isGenerating)
    }

    /// Başarısız üretimin kullanıcıya gösterilecek açıklaması.
    private var errorMessage: String? {
        guard case .failed(let error) = routes.state else { return nil }
        return error.localizedDescription
    }

    /// Bekleme (cooldown) sürerken düğme geri sayımı gösterir.
    private var generateButtonText: String {
        if routes.cooldownRemaining > 0 { return "Wait \(routes.cooldownRemaining)s" }
        return routes.route == nil ? "Generate Route" : "Try Another"
    }

    /// Mesafe girişi: cam kapsül içinde ikon, alan ve birim.
    private var distanceField: some View {
        VStack {
            Text("Enter Distance:")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 15, weight: .semibold))
            HStack {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(.green)
                TextField("Distance", value: $distance, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isDistanceFocused)
                Text("km")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .glassEffect()
    }

    /// Üretilen rotanın özeti. Yedek stratejiyle gelen git-gel rota ayrıca belirtilir.
    private func routeCard(_ route: GeneratedRoute) -> some View {
        HStack(spacing: 8) {
            Image(systemName: route.kind == .loop ? "checkmark.circle.fill" : "arrow.left.arrow.right.circle.fill")
                .foregroundStyle(route.kind == .loop ? .green : .orange)
            Text("\(route.kind == .loop ? "Loop" : "Out & back") — \(route.distanceMeasurement.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2)))))")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .glassEffect(.regular.tint((route.kind == .loop ? Color.green : .orange).opacity(0.2)))
    }

    /// Rotanın tamamını (bir miktar kenar payıyla) içine alan harita bölgesi.
    private func boundingRect(of route: GeneratedRoute) -> MKMapRect {
        let rect = route.polylines.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        return rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15)
    }
}

/// Panel düğmelerinin ortak içeriği. Arka planı düğme stili (cam) çizer;
/// burada yalnızca simge ve metin yer alır.
struct ButtonView: View {
    var text: String
    var symbol: String?
    var isLoading = false

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
            } else if let symbol {
                Image(systemName: symbol)
            }
            Text(text)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .frame(height: 36)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MapView()
}
