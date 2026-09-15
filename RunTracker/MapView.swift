//
//  MapView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit

enum generationState {
    case idle
    case inProgress
    case done
}

struct MapView: View {
    @State private var routeGenerator = RouteGenerator()
    @State private var locationManager = LocationManager()
    @State private var distance: Double = 0.0
    @State private var state: generationState = .idle
    @State private var generatedRoute: GeneratedRoute?
    @State private var generationFailed = false
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @FocusState private var isDistanceFocused: Bool

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                if let route = generatedRoute {
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
            // Mesafe değişince eski rotalar geçersizleşir; geçmişte kalırlarsa
            // üretim tıkandığında yanlış mesafeli rotalar gösterilir.
            .onChange(of: distance) {
                routeGenerator.reset()
            }
        }
    }

    /// Haritanın üzerinde yüzen kontrol paneli. Ayrı cam parçaları tek
    /// `GlassEffectContainer` içinde toplanır ki beliren/kaybolan parçalar
    /// birbirine karışarak (morph) geçiş yapsın.
    private var controlPanel: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 12) {
                if let route = generatedRoute {
                    routeCard(route)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                if generationFailed {
                    Label("No route found. Try a different distance.", systemImage: "exclamationmark.triangle.fill")
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
                        generateRoute()
                    } label: {
                        ButtonView(
                            text: generatedRoute == nil ? "Generate Route" : "Try Another",
                            symbol: "sparkles",
                            isLoading: state == .inProgress
                        )
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
                    .disabled(distance <= 0 || state == .inProgress)
                }

                // Rota hazır olunca navigasyonlu koşu başlatılabilir.
                if let route = generatedRoute {
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
        .animation(.spring(duration: 0.45, bounce: 0.25), value: generatedRoute?.id)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: generationFailed)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: state)
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

    /// Üretilen rotanın özeti.
    private func routeCard(_ route: GeneratedRoute) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(String(format: "Route found — %.2f km", route.distanceInKm))
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .glassEffect(.regular.tint(.green.opacity(0.2)))
    }

    /// Kullanıcının konumundan, girilen mesafede bir döngü rotası üretir ve
    /// kamerayı rotayı gösterecek şekilde ayarlar.
    private func generateRoute() {
        isDistanceFocused = false
        guard let start = locationManager.userLocationCoordinate2D else {
            generationFailed = true
            return
        }
        state = .inProgress
        generationFailed = false

        Task {
            do {
                let route = try await routeGenerator.generateLoop(
                    from: start,
                    targetDistanceMeters: distance * 1000
                )
                generatedRoute = route
                state = .done
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .rect(boundingRect(of: route))
                }
            } catch {
                generatedRoute = nil
                state = .idle
                generationFailed = true
            }
        }
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
