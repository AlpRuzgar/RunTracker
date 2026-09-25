//
//  RunActivityWidget.swift
//  RunTrackerWidgets
//
//  Created by Alp Rüzgar on 23.09.2026.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Koşu ekranlarının kilit ekranı ve Dynamic Island karşılığı.
///
/// Uygulamadaki alt panelin küçültülmüş hâlidir: aynı yuvarlak rakamlar, aynı
/// "değer + küçük etiket" istatistik düzeni, aynı yeşil → mavi gradyan ilerleme
/// çubuğu ve ana düğme. Eklenti `Theme.swift`'i göremediği için ihtiyaç duyulan
/// birkaç parça aşağıda (bkz. `ActivityStyle`) aynı değerlerle tekrarlanır.
struct RunActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenView(kind: context.attributes.kind, state: context.state)
                .padding(16)
                .activitySystemActionForegroundColor(ActivityStyle.green)
        } dynamicIsland: { context in
            let kind = context.attributes.kind
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityIcon(kind: kind, state: state, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: state)
                        .font(.display(22, weight: .bold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Headline(kind: kind, state: state, compact: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        if kind == .navigation {
                            ActivityProgressBar(value: state.progress ?? 0)
                        }
                        HStack(spacing: 14) {
                            if kind == .freeRun {
                                StatBlock(value: ActivityFormat.distance(state.distance), label: "distance")
                            }
                            StatBlock(value: ActivityFormat.pace(state.secondsPerKilometer), label: ActivityFormat.paceLabel)
                            Spacer(minLength: 0)
                            EndButton(state: state)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: ActivityIcon.symbol(kind: kind, state: state))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ActivityStyle.green)
            } compactTrailing: {
                // Navigasyonda en acil bilgi sıradaki dönüşe kalan mesafe;
                // serbest koşuda süre.
                if kind == .navigation, state.phase == .running, let toManeuver = state.distanceToManeuver {
                    Text(ActivityFormat.shortDistance(toManeuver))
                        .font(.display(14, weight: .semibold))
                        .monospacedDigit()
                } else {
                    ElapsedText(state: state)
                        .font(.display(14, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 52, alignment: .trailing)
                }
            } minimal: {
                Image(systemName: ActivityIcon.symbol(kind: kind, state: state))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ActivityStyle.green)
            }
            .keylineTint(ActivityStyle.green)
        }
    }
}

// MARK: - Kilit ekranı

private struct LockScreenView: View {
    let kind: RunActivityAttributes.Kind
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // "End" başlık satırındadır, istatistiklerin yanında değil: dört öğe
            // tek satıra sığmıyor, mesafe kesiliyor ve düğme yazısı kırılıyordu.
            HStack(spacing: 12) {
                ActivityIcon(kind: kind, state: state, size: 44)
                Headline(kind: kind, state: state, compact: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                EndButton(state: state)
            }

            if kind == .navigation {
                ActivityProgressBar(value: state.progress ?? 0)
            }

            HStack(alignment: .center, spacing: 12) {
                if kind == .freeRun {
                    StatBlock(value: ActivityFormat.distance(state.distance), label: "distance")
                    StatDivider()
                }
                StatBlock(label: state.phase == .waitingToStart ? "not started" : "elapsed") {
                    ElapsedText(state: state)
                }
                StatDivider()
                StatBlock(value: ActivityFormat.pace(state.secondsPerKilometer), label: ActivityFormat.paceLabel)
            }
        }
    }
}

// MARK: - Parçalar

/// Başlık satırı: navigasyonda sıradaki manevra, serbest koşuda ekranın adı.
/// Metinler uygulamadaki üst şeritle aynıdır.
private struct Headline: View {
    let kind: RunActivityAttributes.Kind
    let state: RunActivityAttributes.ContentState
    var compact: Bool

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 2) {
            Text(title)
                .font(.system(size: compact ? 15 : 17, weight: .semibold, design: .rounded))
                .foregroundStyle(titleColor)
                .lineLimit(2)
                // Kilit ekranı yüksekliği sınırlı olduğu için sistem metni tek
                // satıra sıkıştırıp uzun talimatları "sağa dö…" diye kesiyordu.
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(compact ? .center : .leading)
            if let subtitle {
                Text(subtitle)
                    .font(.display(compact ? 13 : 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var title: String {
        switch state.phase {
        case .waitingToStart: "Move closer to the route"
        case .rerouting: "Rerouting…"
        case .finished: "Route complete"
        case .ended: "Run saved"
        case .running:
            kind == .navigation
                ? (state.instruction?.isEmpty == false ? state.instruction! : "Follow the route")
                : "Free run"
        }
    }

    private var subtitle: String? {
        switch state.phase {
        case .waitingToStart:
            state.distanceToRoute.map { "\(ActivityFormat.shortDistance($0)) away — starts automatically" }
                ?? "Waiting for your location…"
        case .finished: "Tap End to save your run"
        case .ended: ActivityFormat.distance(state.distance)
        case .rerouting: nil
        case .running:
            kind == .navigation ? state.distanceToManeuver.map { "in \(ActivityFormat.shortDistance($0))" } : nil
        }
    }

    private var titleColor: Color {
        switch state.phase {
        case .rerouting: .primaryBlue
        case .finished, .ended: .secondaryGreen
        default: .primary
        }
    }
}

/// Gradyan daire içinde koşunun o anki simgesi.
private struct ActivityIcon: View {
    let kind: RunActivityAttributes.Kind
    let state: RunActivityAttributes.ContentState
    var size: CGFloat

    var body: some View {
        Image(systemName: Self.symbol(kind: kind, state: state))
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(Color.onAccent)
            .frame(width: size, height: size)
            .background(ActivityStyle.gradient, in: .circle)
    }

    static func symbol(kind: RunActivityAttributes.Kind, state: RunActivityAttributes.ContentState) -> String {
        switch state.phase {
        case .waitingToStart: "figure.walk"
        case .rerouting: "arrow.triangle.2.circlepath"
        case .finished, .ended: "flag.checkered"
        case .running:
            kind == .navigation ? maneuverSymbol(for: state.instruction ?? "") : "figure.run"
        }
    }

    /// MapKit adımları manevra türünü vermez, yalnızca metni verir; ok simgesi
    /// metinden tahmin edilir. Cihaz dili Türkçe olabileceği için iki dilin
    /// anahtar sözcüklerine bakılır; tanınmayan talimat düz ok alır.
    private static func maneuverSymbol(for instruction: String) -> String {
        let text = instruction.lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }

        if has("u-turn", "geri dön") { return "arrow.uturn.down" }
        if has("arrive", "destination", "varış", "hedef") { return "flag.checkered" }
        let slight = has("slight", "keep", "bear", "hafif")
        if has("left", "sola") { return slight ? "arrow.up.left" : "arrow.turn.up.left" }
        if has("right", "sağa") { return slight ? "arrow.up.right" : "arrow.turn.up.right" }
        return "arrow.up"
    }
}

/// Uygulamadaki istatistik bloğu: büyük yuvarlak değer, altında küçük etiket.
private struct StatBlock<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            value
                .font(.display(22, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension StatBlock where Value == Text {
    init(value: String, label: String) {
        self.init(label: label) { Text(value) }
    }
}

private struct StatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 30)
    }
}

/// Geçen süre. Güncelleme beklemeden kendiliğinden işler; koşu başlamadıysa
/// boş, bittiyse donmuş gösterilir.
private struct ElapsedText: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        Group {
            if let finalDuration = state.finalDuration {
                Text(ActivityFormat.duration(finalDuration))
            } else if let startedAt = state.startedAt {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            } else {
                Text("--:--").foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}

/// Uygulamadaki `ProgressBar`'ın aynısı.
private struct ActivityProgressBar: View {
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(ActivityStyle.green.opacity(0.2))
                Capsule(style: .continuous)
                    .fill(ActivityStyle.gradient)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

/// Koşuyu kaydedip bitiren düğme. Kayıt uygulamada yapılır (bkz.
/// `EndRunIntent`). Koşu başlamadan ya da kaydedildikten sonra gösterilmez:
/// başlamamış bir koşuyu kilit ekranından "bitirmek" anlamsız.
private struct EndButton: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if state.phase != .waitingToStart && state.phase != .ended {
            Button(intent: EndRunIntent()) {
                Label("End", systemImage: "stop.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.onAccent)
                    .fixedSize()
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(ActivityStyle.gradient, in: .rect(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Biçim ve stil

/// `Theme.swift`'ten eklentiye gereken parçalar. Değerler oradakiyle aynı
/// tutulmalı; eklenti uygulama modülünü göremediği için paylaşılamıyorlar.
private enum ActivityStyle {
    /// Vurgu renklerinin AÇIK (parlak) değerleri, sabit. Dynamic Island her
    /// zaman siyahtır ve kilit ekranı çoğu zaman koyu görünür; renk katalogu
    /// orada koyu mod varyantlarını veriyor, gradyan boğuk bir lacivertle
    /// bitiyordu. Dolgular bu yüzden katalogdan değil buradan gelir; üstlerindeki
    /// koyu yazı (`onAccent`) ancak bu parlak tonlarda okunur.
    static let green = Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)
    static let blue = Color(red: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255)

    static let gradient = LinearGradient(colors: [green, blue], startPoint: .leading, endPoint: .trailing)
}

private extension Color {
    /// Açık vurgu renklerinin üstündeki koyu yazı; beyaz 3:1'in altında kalıyor
    /// (bkz. `Theme.swift`, `Color.onAccent`).
    static let onAccent = Color(red: 0.10, green: 0.09, blue: 0.08)
}

private extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

private enum ActivityFormat {
    /// Kullanıcının bölgesi mil kullanıyorsa tempo da mil başına yazılır.
    private static var usesMiles: Bool { Locale.current.measurementSystem == .us }

    static var paceLabel: String { usesMiles ? "pace /mi" : "pace /km" }

    /// Tempo, koşucuların alışık olduğu 5'32" biçiminde.
    static func pace(_ secondsPerKilometer: Double?) -> String {
        guard let secondsPerKilometer, secondsPerKilometer.isFinite else { return "--" }
        let seconds = Int((usesMiles ? secondsPerKilometer * 1.609344 : secondsPerKilometer).rounded())
        // Yürürken ya da uzun bir duraklamadan sonra tempo anlamsızlaşır.
        guard seconds < 60 * 60 else { return "--" }
        return "\(seconds / 60)'\(String(format: "%02d", seconds % 60))\""
    }

    /// Koşulan mesafe; uygulamadaki gibi iki ondalık.
    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road,
                                    numberFormatStyle: .number.precision(.fractionLength(2))))
    }

    /// Manevraya/rotaya uzaklık: kısa mesafede metre, uzakta km.
    static func shortDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road,
                                    numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds < 3600 ? .minuteSecond : .hourMinuteSecond))
    }
}

// MARK: - Önizleme

#Preview("Navigation", as: .content, using: RunActivityAttributes(kind: .navigation)) {
    RunActivityWidget()
} contentStates: {
    RunActivityAttributes.ContentState(
        phase: .running, startedAt: .now.addingTimeInterval(-754), distance: 2140,
        secondsPerKilometer: 332, instruction: "Turn left onto Bağdat Caddesi",
        distanceToManeuver: 120, progress: 0.42
    )
    RunActivityAttributes.ContentState(
        phase: .waitingToStart, distance: 0, distanceToRoute: 350
    )
}

#Preview("Free run", as: .dynamicIsland(.expanded), using: RunActivityAttributes(kind: .freeRun)) {
    RunActivityWidget()
} contentStates: {
    RunActivityAttributes.ContentState(
        phase: .running, startedAt: .now.addingTimeInterval(-1260), distance: 3870, secondsPerKilometer: 325
    )
}
