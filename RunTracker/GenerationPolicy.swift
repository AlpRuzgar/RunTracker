//
//  GenerationPolicy.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 15.09.2026.
//

import Foundation

// MARK: - Ayarlar

/// Üretimin tüm ayarları. Saf bir değer tipi; testler ayarları değiştirip
/// (ör. beklemeleri sıfırlayıp) motoru sahte ağla sürer.
///
/// İstek sayısını ayrı bir "bütçe" sınırlamaz: planın kendisi sınırlıdır —
/// `maxLoopAttempts` × `maxEvaluations` tur, şekil başına tek onarım, sayılı
/// toparlanma hakkı ve iki aşamanın süre sınırı. Sürekli hızı `RequestPacer` tutar.
nonisolated struct GenerationPolicy {

    // MARK: Şekil

    /// Döngüdeki köşe sayısı (başlangıç dahil) = bir turdaki bacak/istek sayısı.
    /// Üst sınır 6: köşe sayısı arttıkça döngü daha çok sokağa uğrar, yani
    /// çeşitlilik artar. Tipik üretim artık tek tur sürdüğü (bkz. `acceptance`)
    /// için fazladan köşe patlama kredisinin içinde kalıyor.
    var vertexCountRange = 4...6
    /// Açılış yönüne eklenen sapmanın EN AZI (± derece). Serbest yay genişse
    /// sapma `maxBearingJitter`'a kadar açılır; bkz. `BearingPlanner.leastUsed`.
    var bearingJitter = 20.0
    /// Sapmanın üst sınırı (± derece): serbest yay ne kadar genişse genişlesin
    /// temel yönden bu kadar uzaklaşılır, yoksa "en uzak yön" seçimi anlamsızlaşır.
    var maxBearingJitter = 60.0

    // MARK: Yakınsama

    /// Sapma bunun altına inince yarıçap düzeltmesi durur (±%10).
    var tolerance = 0.10
    /// Döngünün doğrudan kabul edildiği en büyük sapma (±%20). Genişçe tutulur:
    /// ilk tahmin ne kadar sık kabul edilirse düzeltme turunun istekleri o kadar
    /// sık atlanır; hem kota hem bekleme süresi kazanılır. Bu eşik her turun
    /// SONUNDA uygulanır (bkz. `fit`): kabul edilebilir rota bulunduğu anda
    /// yakınsama durur.
    var acceptance = 0.20
    /// Yedeklerin (gevşek döngü, git-gel) kabul sınırı (±%25).
    var fallbackTolerance = 0.25
    /// Bir şekil için en fazla yarıçap turu: 1 ilk tahmin + 2 düzeltme. Orantısal
    /// düzeltme tipik olarak 1 düzeltmede ±%10'a indiği için 2'si pay bırakır.
    var maxEvaluations = 3
    /// Kaç farklı döngü şekli için AĞA GİDİLİR.
    var maxLoopAttempts = 4
    /// Kaç farklı döngü şekli ÜRETİLİP bakılır. Aradaki fark bedava elenenlere
    /// ayrılmıştır (bkz. `maxSkeletonOverlap`): iskeleti son rotaların kopyası
    /// olan şekil, deneme hakkı harcamadan atlanır.
    var maxShapeCandidates = 10
    /// Döngü bulunamazsa kaç yönde git-gel denenecek.
    var fallbackAttempts = 3

    // MARK: Cache ve waypoint

    /// Düzeltme turunda bu kadar (metre) kayan waypoint yerinde bırakılır; bkz.
    /// `LoopShape.pin`. Yarım sokak boyundan (~50 m) kısa: MapKit iki noktayı da
    /// çoğunlukla aynı yola oturtur. Navigasyonun rota dışı eşiğinden (40 m) de
    /// kısa: haritada fark görünmez.
    var pinTolerance = 35.0
    /// Waypoint'in oturtulduğu yol bundan uzaksa (metre) waypoint kullanılamaz
    /// sayılır: su, özel arazi, yolsuz alan.
    var maxSnapDistance = 150.0
    /// Kullanılamayan waypoint pivota doğru bu orana çekilir (şekil başına tek onarım).
    var repairPull = 0.6

    // MARK: Çeşitlilik

    /// Yeni rota, aynı yerden üretilmiş son rotalardan biriyle bu orandan fazla
    /// örtüşürse "aynı rota" sayılır.
    ///
    /// Neden 0.6: Başlangıç bölgesi hariç tutulunca farklı yönlere açılan meşru
    /// döngüler tipik olarak %30'un altında örtüşür; aynı sokaklardan geçen
    /// neredeyse-kopyalar %75'in üstünde. 0.6 bu iki kümenin arasında kalır ve tek
    /// çıkışlı yerlerde (köprü, sahil yolu, park içi tek patika) zorunlu ortak
    /// kısımlara pay bırakır. ≤0.4 bu yerlerde meşru rotaları eler; ≥0.8 neredeyse
    /// aynı rotayı "yeni" diye geçirir. Eşik ne olursa olsun üretimi başarısız
    /// yapamaz: yalnızca örtüşme yüzünden elenen aday yedek olarak saklanır.
    var maxOverlap = 0.6
    /// Örtüşmede "aynı sokak" genişliği (metre): karşı kaldırım + çizgi sapması.
    var overlapCorridor = 25.0
    /// Kuş uçuşu iskelet, son rotalardan birinin koridoruna bu orandan fazla
    /// oturuyorsa şekil AĞA HİÇ GİDİLMEDEN elenir.
    ///
    /// Eskiden benzerlik ancak bacaklar çekildikten sonra anlaşılıyor, elenen her
    /// deneme 4–6 isteği (ve saniyelerce beklemeyi) çöpe atıyordu. Eşik temkinli
    /// (yüksek) tutulur: eleme bedava olduğu için yalnızca bariz kopyaları kesmesi
    /// yeter, meşru bir şekli yanlışlıkla elemek ise gerçek bir kayıptır.
    var maxSkeletonOverlap = 0.75
    /// İskelet karşılaştırmasının koridoru (metre). `overlapCorridor`'dan geniş:
    /// iskelet düz çizgilerden oluşur, gerçek rota ise sokakları takip eder.
    var skeletonCorridor = 50.0
    /// Başlangıç çevresinde örtüşme ve tekrar hesabına katılmayan bölge (metre).
    var startZone = 200.0
    /// Kaç son rotayla karşılaştırılır. Tüm geçmişle karşılaştırmak, bir süre sonra
    /// çevredeki her sokak "kullanılmış" sayılacağı için her yeni rotayı eler.
    var diversityWindow = 3
    /// Aynı sokağı gidip gelerek kullanmanın (çıkmaz sokak sapı) en uzun hâli (metre).
    var maxRepeatedStretch = 120.0

    // MARK: Ağ

    /// Aynı anda uçan en fazla MKDirections isteği. Hızın asıl sınırı
    /// `requestPacing`; buradaki 3 yalnızca patlama kredisiyle giden isteklerin
    /// gecikmesini üst üste bindirir.
    var maxConcurrentRequests = 3
    /// Beklemesiz art arda gönderilebilecek istek sayısı (bkz. `RequestPacer`).
    /// 16: tipik bir üretimin (bir şekil, bir tur, 4–6 bacak) TAMAMI ve arkasından
    /// bir düzeltme turu daha beklemesiz gider. Kritik olan bu: sıradan üretim
    /// patlamanın içinde kalırsa süreyi ağ gecikmesi belirler, hız sınırı değil.
    var requestBurst = 16
    /// Patlama hakkı bitince ardışık istek başlangıçları arasındaki süre. Kota
    /// kısıtı: herhangi bir 60 sn'lik pencerede en fazla `requestBurst` + 60/süre
    /// istek gider; bu toplam (16 + 30 = 46) MapKit'in gözlemlenen throttle
    /// eşiğinin (~50/dk) altında kalmalı. Patlamayı büyütüp aralığı uzatmak,
    /// aynı dakikalık toplamı sıradan üretimin lehine dağıtır.
    var requestPacing: Duration = .seconds(2)
    /// Bir üretimde GEÇİCİ ağ hatasından en fazla kaç kez toparlanılır.
    var maxRecoveries = 3
    /// İlk bekleme; her toparlanmada ikiye katlanır (1 s, 2 s, 4 s). Tek bir cihaz
    /// tek bir sunucuya istek attığı için jitter eklenmez: dağıtılacak kalabalık yok.
    var backoffBase: Duration = .seconds(1)
    /// Throttle'dan toparlanma hakkı: TEK. Throttle penceresi tipik olarak ~1 dk
    /// sürer; kısa üstel bekleme onu aşamaz. Tek uzun bekleme, patlama kenarındaki
    /// tekil throttle'ı affeder; ikinci throttle gerçek kota aşımı demektir ve ağ
    /// işi durdurulup eldeki en iyi adaya düşülür.
    var maxThrottleRecoveries = 1
    /// Throttle sonrası tek beklemenin süresi.
    var throttleBackoff: Duration = .seconds(10)
    /// Döngü aşamasının süre sınırı: dolunca ne yeni deneme ne de yeni DÜZELTME
    /// turu başlatılır, yedeğe geçilir. Başlamış bir tur asla yarıda kesilmez.
    var loopTimeLimit: Duration = .seconds(40)
    /// Yedek aşamasının kendi süre sınırı. Eskiden yedek aşamada hiç süre
    /// kontrolü yoktu: döngü aşaması süresini doldurduktan SONRA yedek bir yarım
    /// dakika daha ekleyebiliyordu. İkisinin toplamı algılanan en kötü süredir.
    var fallbackTimeLimit: Duration = .seconds(20)

    // MARK: Toparlanma

    /// Bir ağ hatası türünden bir üretimde en fazla kaç kez toparlanılır.
    func recoveryLimit(for failure: DirectionsFailure) -> Int {
        switch failure {
        case .throttled: maxThrottleRecoveries
        case .unavailable: maxRecoveries
        }
    }

    /// `n`. toparlanmadan önceki bekleme (n ≥ 1). Geçici hatada üstel, throttle'da
    /// tek uzun bekleme (bkz. `throttleBackoff`).
    func backoff(forRecovery n: Int, after failure: DirectionsFailure) -> Duration {
        switch failure {
        case .throttled: throttleBackoff
        case .unavailable: backoffBase * (1 << max(n - 1, 0))
        }
    }
}
