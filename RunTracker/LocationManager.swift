import CoreLocation

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var userLocation: CLLocation?
    var userLocationCoordinate2D: CLLocationCoordinate2D?
    /// Pusula yönü. Kullanıcı dururken gidiş yönü buradan okunur.
    var userHeading: CLHeading?
    var pathSegments: [[CLLocationCoordinate2D]] = []
    var isTracking = false
    var isManuallyPaused = false
    var isAutoPaused = false
    var isPaused: Bool { isManuallyPaused || isAutoPaused }

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

    func startTracking() {
        pathSegments = []
        isTracking = true
        isManuallyPaused = false
        isAutoPaused = false
        possibleStopTime = nil
    }

    func stopTracking() {
        isTracking = false
        isManuallyPaused = false
        isAutoPaused = false
        possibleStopTime = nil
    }

    func togglePause() {
        isManuallyPaused.toggle()
        if isManuallyPaused {
            possibleStopTime = nil  // manuel duraklatınca auto-pause sayacını sıfırla
        } else {
            pathSegments.append([])
        }
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
        userLocationCoordinate2D = newLocation.coordinate

        guard isTracking, !isManuallyPaused else { return }

        if newLocation.speed < speedThreshold && newLocation.speed >= 0 {
            if possibleStopTime == nil {
                possibleStopTime = Date()
            } else if let stopTime = possibleStopTime,
                      Date().timeIntervalSince(stopTime) > pauseDelay {
                isAutoPaused = true
            }
        } else {
            possibleStopTime = nil
            if isAutoPaused {
                isAutoPaused = false
                pathSegments.append([]) // auto-pause'dan dönünce yeni segment aç
            }
        }

        if !isPaused {
            if pathSegments.isEmpty { pathSegments = [[]] }
                pathSegments[pathSegments.count - 1].append(newLocation.coordinate)
        }
    }
}
