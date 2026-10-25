import CoreLocation
import Foundation

/// デッキの中心地点。実装はアプリの位置情報（Bridges/SwipeDiscoveryEnvironment.swift の AppLocationBridge）。
protocol SwipeLocationProviding {
    /// すでに分かっている現在地。許可がない・まだ取得していない時は nil（既定エリアを使う）。ここでは許可を求めない。
    func currentLocation() async -> CLLocationCoordinate2D?
    /// 「現在地で探す」を押した時だけ呼ぶ。必要なら許可を求めて現在地を取る。
    func requestCurrentLocation() async -> Result<CLLocationCoordinate2D, SwipeLocationError>
}

struct SwipeLocationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
