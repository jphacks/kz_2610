import Combine
import CoreLocation

@MainActor
final class LocationStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var isRequesting = false
    @Published var error: String?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Only called after a deliberate tap; no continuous or background tracking.
    func request() {
        guard !isRequesting else { return }
        error = nil; isRequesting = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default:
            isRequesting = false
            error = "現在地を使うには、iPhoneの設定でmeshinowaの位置情報を許可してください。地図を動かして検索することもできます。"
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRequesting else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .restricted, .denied:
            isRequesting = false
            error = "現在地の利用が許可されていません。地図を動かしてお店を探せます。"
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isRequesting = false
        guard let latest = locations.last, latest.horizontalAccuracy >= 0,
              abs(latest.timestamp.timeIntervalSinceNow) < 120 else {
            error = "現在地を確認できませんでした。もう一度お試しください。"; return
        }
        location = latest
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
        self.error = "現在地を取得できませんでした。通信状況や位置情報の設定を確認してください。"
    }
}
