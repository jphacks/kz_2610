import CoreLocation
import Foundation

/// デッキの中心地点。新しい権限は求めず、すでに「使用中のみ」が許可されている時だけ現在地を使う。
protocol SwipeLocationProviding {
    /// 現在地。許可がない・取得できない時は nil（既定エリアを使う）。
    func currentLocation() async -> CLLocationCoordinate2D?
}

final class SwipeLocationProvider: NSObject, SwipeLocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var requestCount = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    @MainActor
    func currentLocation() async -> CLLocationCoordinate2D? {
        guard isAuthorized else { return nil }
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -300 {
            return recent.coordinate
        }
        guard continuation == nil else { return manager.location?.coordinate }
        requestCount += 1
        let request = requestCount
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            // 取得が遅い時は既定エリアに切り替える（最初のカードを3秒以内に出すため）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.requestCount == request else { return }
                self.finish(with: nil)
            }
        }
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async { self.finish(with: locations.last?.coordinate) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.finish(with: nil) }
    }
}
