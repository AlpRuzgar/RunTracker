import CoreLocation

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var userLocation: CLLocation?
    /// Pusula yönü. Kullanıcı dururken gidiş yönü buradan okunur.
    var userHeading: CLHeading?
    var pathSegments: [[CLLocationCoordinate2D]] = []
    var isTracking = false
    /// Kullanıcı durduğu için kayıt duraklatıldı; hareket edince yeni bir
    /// parça açılır.
    var isPaused = false

    private let speedThreshold: Double = 0.5
    private let pauseDelay: TimeInterval = 3
    private var possibleStopTime: Date?

    /// Kullanıcının gittiği yön (derece). Hareket hâlindeyken GPS'in ölçtüğü
    /// gidiş yönü kullanılır; dururken bu ölçüm anlamsız olduğu için pusulaya
    /// düşülür. İkisi de yoksa yön bilinmiyor demektir.
    var travelDirection: Double? {
        if let userLocation, userLocation.speed > 1,
           userLocation.courseAccuracy >= 0, userLocation.course >= 0 {
            return userLocation.course
        }
        guard let userHeading, userHeading.headingAccuracy >= 0 else { return nil }
        return userHeading.trueHeading >= 0 ? userHeading.trueHeading : userHeading.magneticHeading
    }

    override init() {
        super.init()
        manager.delegate = self
        // Pusula her derecelik oynamada haber vermesin; kamera boş yere sallanır.
        manager.headingFilter = 3
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Koşu ekranı açıkken telefon kilitlense de konum gelmeye devam etsin mi?
    ///
    /// Eskiden ekran kilitlenince uygulama askıya alınıyor, kilitliyken
    /// koşulan kısım kayda hiç girmiyor ve Live Activity donuyordu. Yalnızca
    /// koşu ekranları açar; diğer ekranların (harita, hava durumu) arka planda
    /// konum tüketmesi için bir sebep yok. "Kullanımdayken" izni yeterlidir,
    /// sistem bu sürede mavi konum göstergesini gösterir.
    func setRunsInBackground(_ enabled: Bool) {
        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
        #endif
        // Sistemin "kullanıcı duruyor" tahminiyle güncellemeleri kesmesi,
        // trafik ışığında bekleyen koşucunun kaydını da kesiyordu.
        manager.pausesLocationUpdatesAutomatically = !enabled
        manager.activityType = enabled ? .fitness : .other
    }

    func startTracking() {
        pathSegments = []
        isTracking = true
        isPaused = false
        possibleStopTime = nil
    }

    func stopTracking() {
        isTracking = false
        isPaused = false
        possibleStopTime = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            // Delegate atanır atanmaz bu metot çağrıldığı için izin isteği
            // uygulamanın ilk açılışında kendiliğinden çıkar.
            requestPermission()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Negatif doğruluk, pusulanın (manyetik girişim, kalibrasyonsuzluk)
        // güvenilir bir ölçüm veremediği anlamına gelir.
        guard newHeading.headingAccuracy >= 0 else { return }
        userHeading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        userLocation = newLocation

        guard isTracking else { return }

        if newLocation.speed < speedThreshold && newLocation.speed >= 0 {
            if possibleStopTime == nil {
                possibleStopTime = Date()
            } else if let stopTime = possibleStopTime,
                      Date().timeIntervalSince(stopTime) > pauseDelay {
                isPaused = true
            }
        } else {
            possibleStopTime = nil
            if isPaused {
                isPaused = false
                pathSegments.append([]) // duraklamadan dönünce yeni segment aç
            }
        }

        if !isPaused {
            if pathSegments.isEmpty { pathSegments = [[]] }
            pathSegments[pathSegments.count - 1].append(newLocation.coordinate)
        }
    }
}
