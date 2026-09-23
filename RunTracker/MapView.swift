//
//  MapView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 7.09.2026.
//

import SwiftUI
import MapKit
import SwiftData

struct MapView: View {
    /// Uygulama genelinde paylaşılan tek üretim motoru (bkz. `RunTrackerApp`).
    @Environment(RouteViewModel.self) private var routes
    @Environment(User.self) private var user
    @State private var locationManager = LocationManager()
    @State private var distance: Double = 0
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @FocusState private var isDistanceFocused: Bool

    @State private var isShowingFavorites = false
    /// Rota ters yönde mi koşulacak? Seçim navigasyon başlamadan önce yapılır.
    @State private var isReversed = false
    /// Haritanın kuzeye göre dönüklüğü; oklar buna göre hizalanır.
    @State private var mapHeading = 0.0
    /// Haritada gösterilen rota ve yön okları. Kamera her oynadığında yeniden
    /// hesaplanmasın diye saklanır; yalnızca rota ya da yön seçimi değişince
    /// güncellenir (bkz. `refreshPreview`).
    @State private var previewPolylines: [MKPolyline] = []
    @State private var arrows: [RouteArrow] = []
    /// Tam ekran açılacak navigasyon; `nil` ise navigasyon kapalı.
    @State private var navigatingRoute: GeneratedRoute?
    @State private var isFreeRunning = false

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            RouteOverlay(polylines: previewPolylines, tint: .secondaryGreen,
                         mapHeading: mapHeading, arrows: arrows)
        }
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
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
        .overlay(alignment: .topLeading) { favoritesButton }
        .safeAreaInset(edge: .bottom) { controlPanel }
        // Rota ve oklar rota değişince (ve ekran açılırken) bir kez
        // hesaplanır; kamerayı çerçeveleyen `onChange`e karışmaz, yoksa
        // sekmeye her dönüşte harita kullanıcının baktığı yerden rotaya
        // geri sıçrardı.
        .task(id: routes.route?.id) {
            refreshPreview()
        }
        // Yön değişince oklar da dönsün: kullanıcı "Reversed" seçtiğinde
        // haritada gerçekten koşacağı yönü görmeli.
        .onChange(of: isReversed) {
            refreshPreview()
        }
        // Yeni rota gelince kamera onu tamamen gösterecek şekilde kayar.
        // Üretim sürerken gösterilen önceki rotanın kimliği değişmez.
        .onChange(of: routes.route?.id) {
            guard case .ready(let route) = routes.state else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                cameraPosition = .rect(boundingRect(of: route))
            }
        }
        .onAppear {
            // Hedef mesafe profilden gelir: kullanıcı her seferinde aynı
            // sayıyı yazmak zorunda kalmasın.
            if distance == 0 { distance = user.targetDistance }
        }
        .sheet(isPresented: $isShowingFavorites) {
            FavoritePathsSheet()
        }
        // Navigasyon tam ekran açılır: kendi başına bir ekrandır, haritanın
        // üstüne itilmiş bir sayfa değil.
        .fullScreenCover(item: $navigatingRoute) { route in
            NavigationView(route: route, isReversed: isReversed)
        }
        // Serbest koşu da tam ekran: koşu ekranları gezinme çubuğu taşımaz.
        .fullScreenCover(isPresented: $isFreeRunning) {
            FreeRunView()
        }
    }

    // MARK: - Harita üstü denetimler

    private var favoritesButton: some View {
        Button {
            isShowingFavorites = true
        } label: {
            Image(systemName: "star.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondaryGreen)
                .padding(11)
        }
        .glassVisual(.regular, in: .circle)
        .padding(.leading, Metrics.gutter)
        .padding(.top, 8)
        .accessibilityLabel("Favorite paths")
    }

    /// Haritanın üstünde yüzen tek panel.
    ///
    /// Eskiden burada birbirinden ayrı beş cam parça vardı ve ekranın yarısını
    /// kaplıyordu. Hepsi tek bir kartta toplandı: harita asıl içerik, panel ise
    /// onun üstünde duran ince bir şerit olmalı.
    private var controlPanel: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 12) {
                if let status = routes.progressDescription {
                    statusLine(status, systemImage: "location.magnifyingglass", tint: .secondary)
                } else if let errorMessage {
                    statusLine(errorMessage, systemImage: "exclamationmark.triangle.fill", tint: .red)
                }

                if case .ready(let route) = routes.state {
                    routeSummary(route)
                    directionPicker
                }

                distanceRow

                HStack(spacing: 10) {
                    Button {
                        isDistanceFocused = false
                        isFreeRunning = true
                    } label: {
                        Label("Free run", systemImage: "figure.run")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        isDistanceFocused = false
                        routes.generate(from: locationManager.userLocationCoordinate2D,
                                        targetKilometers: distance)
                    } label: {
                        if routes.isGenerating {
                            ProgressView().tint(Color.onAccent)
                        } else {
                            Label(generateButtonText, systemImage: generateButtonSymbol)
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(distance <= 0 || routes.isGenerating || routes.cooldownRemaining > 0)
                }

                if case .ready(let route) = routes.state {
                    Button {
                        isDistanceFocused = false
                        navigatingRoute = route
                    } label: {
                        Label("Start navigation", systemImage: "location.north.fill")
                            .foregroundStyle(.white)
                    }
                    // Koşuyu başlatan eylem secondaryGreen: rotanın haritadaki rengi
                    // de o, ikisi aynı şeyi anlatıyor.
                    .buttonStyle(PrimaryButtonStyle(tint: .secondaryGreen))
                }
            }
            .padding(16)
            .glassVisual(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 6)
        }
        .animation(.snappy(duration: 0.35), value: routes.route?.id)
        .animation(.snappy(duration: 0.35), value: errorMessage)
        .animation(.snappy(duration: 0.35), value: routes.progressDescription)
    }

    /// Üretilen rotanın tek satırlık özeti.
    private func routeSummary(_ route: GeneratedRoute) -> some View {
        HStack(spacing: 8) {
            Image(systemName: route.kind == .loop ? "arrow.trianglehead.clockwise" : "arrow.left.arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondaryGreen)
            Text(route.kind == .loop ? "Loop" : "Out & back")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            Text(route.distanceMeasurement.formatted(
                .measurement(width: .abbreviated, usage: .road,
                             numberFormatStyle: .number.precision(.fractionLength(2))))
            )
            .font(.display(17, weight: .semibold))
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusLine(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Rotanın hangi yönde koşulacağı. Ters yön aynı çizgiyi ters sırada takip
    /// eder; yönü haritadaki oklar gösterir (bkz. `ReversedPath`).
    private var directionPicker: some View {
        Picker("Direction", selection: $isReversed) {
            Text("Forward").tag(false)
            Text("Reversed").tag(true)
        }
        .pickerStyle(.segmented)
        .simultaneousGesture(TapGesture().onEnded { isDistanceFocused = false })
    }

    /// Mesafe girişi: etiket, alan ve birim tek satırda.
    private var distanceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondaryGreen)

            Text("Distance")
                .font(.system(size: 15, weight: .medium, design: .rounded))

            Spacer()

            TextField("5", value: $distance, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .focused($isDistanceFocused)
                .multilineTextAlignment(.trailing)
                .font(.display(19, weight: .semibold))
                .frame(maxWidth: 74)

            Text("km")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))
    }

    // MARK: - Yardımcılar

    /// Haritada gösterilecek çizgileri ve okları hesaplar. Ters yön seçiliyse
    /// çevrilmiş rota çizilir: çizgi ikisinde de aynı olduğu için yönü yalnızca
    /// oklar ayırt eder.
    private func refreshPreview() {
        guard let route = routes.route else {
            previewPolylines = []
            arrows = []
            return
        }
        let path: any FollowablePath = isReversed ? route.reversed() : route
        previewPolylines = path.polylines
        arrows = RouteArrow.along(previewPolylines)
    }

    /// Başarısız üretimin kullanıcıya gösterilecek açıklaması.
    private var errorMessage: String? {
        guard case .failed(let error) = routes.state else { return nil }
        return error.localizedDescription
    }

    private var generateButtonText: String {
        if routes.cooldownRemaining > 0 { return "Wait \(routes.cooldownRemaining)s" }
        return routes.route == nil ? "Generate" : "Try another"
    }

    private var generateButtonSymbol: String {
        routes.cooldownRemaining > 0 ? "hourglass" : "sparkles"
    }

    /// Rotanın tamamını (bir miktar kenar payıyla) içine alan harita bölgesi.
    private func boundingRect(of route: GeneratedRoute) -> MKMapRect {
        route.polylines.framingRect(padding: 0.15)
    }
}

#Preview {
    MapView()
        .environment(RouteViewModel())
        .environment(
            User(name: "Alp", sex: .male, bday: .now, heightCM: 175,
                 weightKG: 70, targetDistance: 5, motivation: .hobby)
        )
}
