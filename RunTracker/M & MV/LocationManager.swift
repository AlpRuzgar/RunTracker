import CoreLocation

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var userLocation: CLLocation?
    var userLocationCoordinate2D: CLLocationCoordinate2D?
    var pathSegments: [[CLLocationCoordinate2D]] = []
    var isTracking = false
    var isManuallyPaused = false
    var isAutoPaused = false
    var isPaused: Bool { isManuallyPaused || isAutoPaused }

    private let speedThreshold: Double = 0.5
    private let pauseDelay: TimeInterval = 3
    private var possibleStopTime: Date?

    override init() {
        super.init()
        manager.delegate = self
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
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
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
