import CoreGraphics
import Foundation

/// 動きと判定の初期値（要件定義書 6章）。実機で調整しやすいよう、ここにまとめる。
enum SwipeGestureConstants {
    /// 横移動量がカード幅のこの割合以上なら確定。
    static let commitDistanceRatio: CGFloat = 0.35
    /// 指を離した時の予測終点がカード幅のこの割合以上なら確定。
    static let commitPredictedRatio: CGFloat = 0.60
    /// カードの最大の傾き（度）。
    static let maxRotationDegrees: Double = 15
    /// オーバーレイの最大の濃さ。
    static let maxOverlayOpacity: Double = 0.85
    /// 画面外へ飛ばす時間（秒）。
    static let flyOutDuration: Double = 0.25
    /// タップとみなす総移動距離の上限（pt、未満）。
    static let tapMaxDistance: CGFloat = 5
    /// タップとみなす触れていた時間の上限（秒、未満）。
    static let tapMaxDuration: TimeInterval = 0.3
}

/// カード上のタップの行き先。
enum SwipeTapTarget: Equatable {
    case previousPhoto
    case nextPhoto
    case map
    case detail
    case none
}

/// 指を離した時の結果。
enum SwipeReleaseOutcome: Equatable {
    /// 短く触れただけ。
    case tap(SwipeTapTarget)
    /// 5pt未満だが長く押した。何もしない。
    case longPress
    /// しきい値を超えたので確定。
    case commit(SwipeDecisionKind)
    /// しきい値未満。元の位置に戻す。
    case cancel
}

/// タップの振り分けに使うカード内の領域（カードの座標系）。
struct SwipeCardRegions: Equatable {
    var size: CGSize
    var locationInset: CGRect
    var infoArea: CGRect
    /// 写真を表示中なら true。星評価ビューの左右タップは何もしない。
    var showsPhotos: Bool

    static let empty = SwipeCardRegions(size: .zero, locationInset: .null, infoArea: .null, showsPhotos: false)
}

/// しきい値判定、タップとドラッグの判別。SwiftUI に依存しない純粋関数。
enum SwipeGestureEvaluator {
    /// タップかどうか（総移動距離5pt未満かつ0.3秒未満）。
    static func isTap(maxDistance: CGFloat, duration: TimeInterval) -> Bool {
        maxDistance < SwipeGestureConstants.tapMaxDistance && duration < SwipeGestureConstants.tapMaxDuration
    }

    /// 指を離した時の判定。
    /// - Parameters:
    ///   - maxDistance: 触れている間に指が動いた最大の距離（開始点から）。
    ///   - duration: 触れていた時間。
    ///   - location: 指を離した位置（カードの座標系）。
    static func evaluateRelease(maxDistance: CGFloat, duration: TimeInterval,
                                translation: CGSize, predictedEndTranslation: CGSize,
                                location: CGPoint, regions: SwipeCardRegions) -> SwipeReleaseOutcome {
        if maxDistance < SwipeGestureConstants.tapMaxDistance {
            return isTap(maxDistance: maxDistance, duration: duration)
                ? .tap(tapTarget(at: location, regions: regions))
                : .longPress
        }
        if let kind = commitKind(translation: translation, predictedEndTranslation: predictedEndTranslation,
                                 cardWidth: regions.size.width) {
            return .commit(kind)
        }
        return .cancel
    }

    /// 右＝行きたい、左＝イマイチ。しきい値に届かなければ nil。
    static func commitKind(translation: CGSize, predictedEndTranslation: CGSize, cardWidth: CGFloat) -> SwipeDecisionKind? {
        guard cardWidth > 0 else { return nil }
        let x = translation.width, predicted = predictedEndTranslation.width
        if abs(x) >= cardWidth * SwipeGestureConstants.commitDistanceRatio {
            return x > 0 ? .interested : .notInterested
        }
        // 勢いで判定するのは、指が動いた向きと同じ向きに投げた時だけ。
        if abs(predicted) >= cardWidth * SwipeGestureConstants.commitPredictedRatio, x == 0 || (x > 0) == (predicted > 0) {
            return predicted > 0 ? .interested : .notInterested
        }
        return nil
    }

    /// ドラッグ中に確定しきい値（距離）を超えているか。触覚フィードバックとオーバーレイに使う。
    static func kindPastThreshold(translationX: CGFloat, cardWidth: CGFloat) -> SwipeDecisionKind? {
        guard cardWidth > 0, abs(translationX) >= cardWidth * SwipeGestureConstants.commitDistanceRatio else { return nil }
        return translationX > 0 ? .interested : .notInterested
    }

    /// 横移動量に比例した傾き（度）。最大 ±15°。
    static func rotationDegrees(translationX: CGFloat, cardWidth: CGFloat) -> Double {
        guard cardWidth > 0 else { return 0 }
        let ratio = Double(translationX / (cardWidth * SwipeGestureConstants.commitDistanceRatio))
        return max(-1, min(1, ratio)) * SwipeGestureConstants.maxRotationDegrees
    }

    /// 移動量0〜しきい値で 0〜0.85 に変わるオーバーレイの濃さ。
    static func overlayOpacity(translationX: CGFloat, cardWidth: CGFloat) -> Double {
        guard cardWidth > 0 else { return 0 }
        let ratio = Double(abs(translationX) / (cardWidth * SwipeGestureConstants.commitDistanceRatio))
        return min(1, ratio) * SwipeGestureConstants.maxOverlayOpacity
    }

    /// 指を離した位置でタップの行き先を決める。
    static func tapTarget(at point: CGPoint, regions: SwipeCardRegions) -> SwipeTapTarget {
        if regions.locationInset.contains(point) { return .map }
        if regions.infoArea.contains(point) { return .detail }
        guard regions.showsPhotos, CGRect(origin: .zero, size: regions.size).contains(point) else { return .none }
        return point.x < regions.size.width / 2 ? .previousPhoto : .nextPhoto
    }

    /// 開始点からの距離。
    static func distance(of translation: CGSize) -> CGFloat {
        sqrt(translation.width * translation.width + translation.height * translation.height)
    }
}
