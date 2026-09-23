//
//  Theme.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 22.09.2026.
//

import SwiftUI

// MARK: - Tasarım dili
//
// Uygulamanın görünümü tek yerden gelir: renk rolleri, tipografi ve kart/düğme
// biçimleri. Görünümler bunları kullanır, kendi başlarına renk ve gölge
// uydurmaz — aksi hâlde aynı kart her ekranda birazcık farklı çıkar.
//
// Palet: SERİN ve nötr. Zemin gerçek beyaz (koyu modda gerçek siyah), kartlar
// bunun üstünde hafifçe ayrışan bir gri; renk yalnızca vurguda kullanılır. İki
// vurgu rengi ve rolleri:
//
// - `secondaryGreen`: BİRİNCİL. Eylem, odak, seçim ve başarı — ana düğmeler, seçili
//   sekme, AccentColor, favori/tamamlanan durumlar, rota çizgisi.
// - `primaryBlue`: İKİNCİL. Geçici/anlık durumlar ve ayırt edici ikincil bilgi —
//   yeniden yönlendirme, takip/duraklat anahtarları, serbest koşu (rotaya
//   karşı), hava durumu kartının "gündüz" ucu.
//
// Birincil düğme ve ilerleme çubukları artık düz dolgu değil, secondaryGreen →
// primaryBlue GRADIENT: `Color.brandGradient` (bkz. altta).

extension Color {
    /// Vurgu renklerinin ÜSTÜNE gelen yazı ve simge rengi.
    ///
    /// Hem `secondaryGreen` (#10B981) hem `primaryBlue` (#38BDF8) açık tonlardır:
    /// beyaz yazıyla kontrastları 3:1'in altında kalır, yani küçük metin
    /// okunmaz. Koyu yazı ikisinde de 7:1'in üstüne çıkar. Dolgulu düğmelerin
    /// yazısı bu yüzden koyudur — bir stil tercihi değil, okunabilirlik.
    static let onAccent = Color(red: 0.10, green: 0.09, blue: 0.08)

    /// Uygulamanın imza gradyanı: secondaryGreen → primaryBlue. Birincil düğmeler ve
    /// ilerleme çubukları bunu kullanır; markayı düz bir vurgu rengi yerine
    /// bir geçişle taşır.
    static let brandGradient = LinearGradient(
        colors: [.secondaryGreen, .primaryBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Tipografi

extension Font {
    /// Sayılar ve başlıklar için yuvarlak kesim. Mesafe, süre, tempo gibi
    /// uygulamanın asıl içeriği sayılardır; yuvarlak rakamlar hem sıcak durur
    /// hem de tek tek okunması gereken değerlerde daha nettir.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Ekran başlığı.
    static let screenTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    /// Kart başlığı.
    static let cardTitle = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// Büyük sayı (istatistik kutusu, koşu ekranı).
    static let statValue = Font.system(size: 22, weight: .semibold, design: .rounded)
}

// MARK: - Ölçüler

enum Metrics {
    /// Ekran kenar boşluğu.
    static let gutter: CGFloat = 20
    /// Kart köşesi. Sürekli (continuous) eğri kullanılır: iOS'un kendi
    /// yüzeyleriyle aynı yumuşaklık.
    static let radius: CGFloat = 22
    /// Küçük öğeler (rozet, küçük resim, alan) için köşe.
    static let smallRadius: CGFloat = 14
    /// Kartlar arası dikey boşluk.
    static let stack: CGFloat = 16
}

// MARK: - Yüzeyler

/// Kart: krem zeminin üstünde duran beyaz yüzey.
///
/// Gölge bilerek çok yumuşak ve neredeyse görünmez; ayrımı asıl yapan saç teli
/// inceliğindeki kenar çizgisidir. Koyu gölge, sıcak paleti kirletip arayüzü
/// ağırlaştırıyordu.
private struct CardSurface: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

extension View {
    /// Standart kart yüzeyi.
    func card(padding: CGFloat = 18, radius: CGFloat = Metrics.radius) -> some View {
        modifier(CardSurface(padding: padding, radius: radius))
    }

    /// Ekranın beyaz/siyah zemini, tepede imza renklerinden bir gradyan yaldızla.
    ///
    /// Gezinme çubuğu da aynı düz zemin rengini alır ve GÖRÜNÜR tutulur: yoksa
    /// kaydırma sırasında kartlar durum çubuğunun altına girip saatin üstünden
    /// geçiyor, ekranın tepesi kirli görünüyordu. Düz `Color.canvas` katmanı bu
    /// yüzden TEK BAŞINA `ignoresSafeArea()` alır — çubuğun rengiyle birebir
    /// eşleşsin, aralarında çizgi kalmasın. Gradyan katmanı ise güvenli alanı
    /// göz ardı ETMEZ: çubuğun altına sızsaydı, düz renkli çubukla renkli
    /// gradyan arasında sert bir sınır (koyu modda siyah bir şerit) oluşuyordu.
    func screenBackground() -> some View {
        background(alignment: .top) {
            ZStack(alignment: .top) {
                Color.canvas.ignoresSafeArea()
                LinearGradient(
                    colors: [Color.secondaryGreen, Color.primaryBlue, .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Başlıklar

/// Bölüm başlığı: küçük, seyrek harf aralıklı, ikincil renkte. Kartın içindeki
/// asıl içeriği bastırmadan onu adlandırır.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ekranın üst başlığı: büyük yuvarlak başlık ve isteğe bağlı alt satır.
struct ScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let subtitle {
                Text(subtitle)
                    .font(.screenTitle)
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.screenTitle)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - İstatistik

/// Tek bir ölçüm: üstte küçük etiket, altta büyük yuvarlak değer.
///
/// Etiket üstte, değer altta: göz önce neye baktığını öğrenir, sonra değeri
/// okur. Değerler `monospacedDigit` ile yazılır, yoksa canlı güncellenen süre
/// ve mesafe her rakam değişiminde sağa sola oynar.
struct StatView: View {
    var title: String
    var stat: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(stat)
                .font(.statValue.monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - İlerleme

/// İnce, yuvarlak uçlu ilerleme çubuğu. Sistemin `ProgressView`'ı yerine
/// kullanılır: yüksekliği ve rengi kontrol edilebildiği için hedef çubuğu
/// kartın içinde bir çizgi gibi durur, bir denetim gibi değil.
struct ProgressBar: View {
    /// 0...1.
    var value: Double
    var tint: Color = .secondaryGreen
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [tint, .primaryBlue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.snappy, value: value)
    }
}

// MARK: - Düğmeler

/// Ana eylem: secondaryGreen → primaryBlue gradyan dolgu, koyu yazı (bkz. `Color.onAccent`).
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .secondaryGreen

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(isEnabled ? Color.onAccent : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                if isEnabled {
                    LinearGradient(colors: [tint, .primaryBlue], startPoint: .leading, endPoint: .trailing)
                } else {
                    Color.hairline
                }
            }
            .clipShape(.rect(cornerRadius: Metrics.smallRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// İkincil eylem: yüzey dolgusu, saç teli kenar. Ana eylemle aynı ağırlıkta
/// görünmemesi için renk taşımaz.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.surface, in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Boş durumlar

/// "Henüz bir şey yok" hâli. Boş bir ekranda tek bir gri cümle bırakmak yerine
/// ne olacağını söyler: kullanıcı bir şeyin bozuk olduğunu sanmaz.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondaryGreen)
            Text(title)
                .font(.cardTitle)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

// MARK: - Harita üstü denetimler

/// Haritanın üstünde yüzen denetimlerin ortak zemini.
///
/// Cam etkisi yalnızca BURADA kullanılır. Haritanın üstünde altını görmek
/// gerekir ve harita görüntüsü her yerde farklıdır; düz bir dolgu ya okunmaz ya
/// da haritayı gereksiz yere örter. Diğer ekranlarda cam yok: sakin, düz kartlar.
extension View {
    func mapControlSurface(radius: CGFloat = Metrics.radius) -> some View {
        padding(14)
            .glassVisual(.regular, in: .rect(cornerRadius: radius, style: .continuous))
    }
}

enum CamStili {
    case regular
    case clear

    var glass: Glass {
        switch self {
        case .regular: .regular
        case .clear:   .clear
        }
    }

    func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = glass
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    func glassVisual(
        _ stil: CamStili = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        in shape: some Shape = Capsule()
    ) -> some View {
        glassEffect(stil.glass(tint: tint, interactive: interactive), in: shape)
    }
}
