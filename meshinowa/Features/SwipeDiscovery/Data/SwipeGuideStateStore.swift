import Foundation

/// ガイドの完了状態と補助矢印の残り枚数。既存のキーには触れず、`swipeDiscovery.` で始まるキーだけを使う。
final class SwipeGuideStateStore {
    static let guideCompletedKey = "swipeDiscovery.guideCompleted"
    static let hintRemainingKey = "swipeDiscovery.hintRemaining"
    /// 初めての右スワイプで「保存しました」を出したか。
    static let savedNoticeShownKey = "swipeDiscovery.savedNoticeShown"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var state: SwipeGuideState {
        get {
            let completed = defaults.bool(forKey: Self.guideCompletedKey)
            let remaining = defaults.object(forKey: Self.hintRemainingKey) as? Int ?? SwipeGuidePolicy.hintCount
            return SwipeGuideState(guideCompleted: completed, hintRemaining: max(0, remaining))
        }
        set {
            defaults.set(newValue.guideCompleted, forKey: Self.guideCompletedKey)
            defaults.set(newValue.hintRemaining, forKey: Self.hintRemainingKey)
        }
    }

    var savedNoticeShown: Bool {
        get { defaults.bool(forKey: Self.savedNoticeShownKey) }
        set { defaults.set(newValue, forKey: Self.savedNoticeShownKey) }
    }
}
