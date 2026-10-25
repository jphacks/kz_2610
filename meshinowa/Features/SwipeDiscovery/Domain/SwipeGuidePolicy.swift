import CoreGraphics
import Foundation

/// スワイプガイドの状態（UserDefaults に保存する値）。
struct SwipeGuideState: Equatable {
    var guideCompleted: Bool
    var hintRemaining: Int

    static let initial = SwipeGuideState(guideCompleted: false, hintRemaining: SwipeGuidePolicy.hintCount)
}

enum SwipeGuideMode: Equatable {
    /// 初回ガイド：矢印をはっきり出し、お手本の動きを見せる。
    case initial
    /// 補助矢印：薄く出し、ドラッグ中は進む側だけ濃くする。
    case hint
    /// 出さない。
    case none
}

/// ガイドの表示判定。純粋関数。
enum SwipeGuidePolicy {
    /// ガイド完了後に補助矢印を出す枚数。
    static let hintCount = 5
    /// 補助矢印の普段の濃さ。
    static let hintOpacity: Double = 0.4
    /// ドラッグ中、反対側の矢印の濃さ。
    static let oppositeOpacity: Double = 0.2
    /// お手本の動きで、カードが動いている側の矢印の拡大率。
    static let demoEmphasisScale: CGFloat = 1.15
    /// 最初のカードが出てからガイドを出すまでの時間。
    static let appearDelay: TimeInterval = 0.4
    /// お手本の動きの横移動量（pt）と1回の長さ（秒）、繰り返し回数。
    static let demoTravel: CGFloat = 40
    static let demoCycleDuration: TimeInterval = 2.4
    static let demoRepeatCount = 2

    static func mode(for state: SwipeGuideState) -> SwipeGuideMode {
        if !state.guideCompleted { return .initial }
        return state.hintRemaining > 0 ? .hint : .none
    }

    /// スワイプかボタンで1枚判断した後の状態。1枚目で初回ガイドが完了し、その後は1枚ごとに補助矢印を減らす。
    static func afterDecision(_ state: SwipeGuideState) -> SwipeGuideState {
        guard state.guideCompleted else {
            return SwipeGuideState(guideCompleted: true, hintRemaining: hintCount)
        }
        return SwipeGuideState(guideCompleted: true, hintRemaining: max(0, state.hintRemaining - 1))
    }

    /// 「スワイプの使い方を見る」（F-23）で初期値に戻す。「戻す」では呼ばない。
    static func reset() -> SwipeGuideState { .initial }

    /// 左（イマイチ）・右（気になる）の矢印の濃さ。
    /// - Parameter dragX: ドラッグ中の横移動量。0 ならドラッグしていない。
    static func arrowOpacities(mode: SwipeGuideMode, dragX: CGFloat) -> (left: Double, right: Double) {
        let base: Double
        switch mode {
        case .none: return (0, 0)
        case .initial: base = 1
        case .hint: base = hintOpacity
        }
        if dragX > 0 { return (oppositeOpacity, 1) }
        if dragX < 0 { return (1, oppositeOpacity) }
        return (base, base)
    }
}
