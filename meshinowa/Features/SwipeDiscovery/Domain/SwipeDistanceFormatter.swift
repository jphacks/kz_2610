import Foundation

/// 「650m・徒歩約8分」の書式。徒歩は分速80mで割って四捨五入した目安で、正確な経路時間は地図アプリに任せる。
enum SwipeDistanceFormatter {
    static let walkingMetersPerMinute: Double = 80

    static func walkingMinutes(meters: Double) -> Int {
        max(1, Int((max(0, meters) / walkingMetersPerMinute).rounded()))
    }

    /// 1km未満は10m単位、10km未満は0.1km単位、それ以上は1km単位。
    static func distanceText(meters: Double) -> String {
        let value = max(0, meters)
        if value < 995 {
            return "\(max(10, Int((value / 10).rounded()) * 10))m"
        }
        if value < 9_950 {
            let km = (value / 100).rounded() / 10
            return String(format: "%.1fkm", km)
        }
        return "\(Int((value / 1000).rounded()))km"
    }

    /// カードの距離ラベル。
    static func label(meters: Double) -> String {
        "\(distanceText(meters: meters))・徒歩約\(walkingMinutes(meters: meters))分"
    }

    /// VoiceOver 用。
    static func accessibilityLabel(meters: Double) -> String {
        "\(distanceText(meters: meters))、徒歩約\(walkingMinutes(meters: meters))分"
    }

    /// 半径の表示（500m／1km／50km）。
    static func radiusText(meters: Double) -> String {
        meters < 1000 ? "\(Int(meters))m" : (meters.truncatingRemainder(dividingBy: 1000) == 0
            ? "\(Int(meters / 1000))km" : String(format: "%.1fkm", meters / 1000))
    }
}
