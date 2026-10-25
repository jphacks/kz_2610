import Foundation

/// 判断記録の期限と、既存の保存状態との整合（v6）。デッキと結果一覧の両方が同じ判定を使う。
/// 「残す記録」と「消す記録」を返すだけで、ファイルへの反映は SwipeDecisionStore が行う。
enum SwipeDecisionReconciler {
    /// イマイチをデッキに出さない期間（24時間）。
    static let notInterestedLifetime: TimeInterval = 86_400

    struct Result: Equatable {
        let kept: [SwipeDecision]
        let removed: [SwipeDecision]

        var removedIDs: Set<String> { Set(removed.map(\.id)) }
    }

    /// - Parameters:
    ///   - now: 現在時刻。テストでは固定する。
    ///   - isExcluded: 「行きたい」「行った」「自分のレビュー済み」のどれかに入っていれば true。
    static func reconcile(_ decisions: [SwipeDecision], now: Date,
                          isExcluded: (String) -> Bool) -> Result {
        var kept: [SwipeDecision] = []
        var removed: [SwipeDecision] = []
        for decision in decisions {
            let keep: Bool
            switch decision.kind {
            case .notInterested:
                keep = elapsed(since: decision.decidedAt, now: now) < notInterestedLifetime
            case .interested:
                keep = isExcluded(decision.id)
            }
            if keep { kept.append(decision) } else { removed.append(decision) }
        }
        return Result(kept: kept, removed: removed)
    }

    /// 判断からの経過秒数。端末の時計が戻って判断日時が未来になった時は 0 として扱う。
    static func elapsed(since date: Date, now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(date))
    }

    /// イマイチが再び候補に出るまでの残り時間（時間単位、切り上げ）。
    static func hoursUntilReturn(_ decision: SwipeDecision, now: Date) -> Int {
        let remaining = notInterestedLifetime - elapsed(since: decision.decidedAt, now: now)
        guard remaining > 0 else { return 0 }
        return Int((remaining / 3600).rounded(.up))
    }

    /// 24時間以内のイマイチがあるか（「イマイチをリセット」を出すかどうか）。
    static func hasActiveNotInterested(_ decisions: [SwipeDecision], now: Date) -> Bool {
        decisions.contains { $0.kind == .notInterested && elapsed(since: $0.decidedAt, now: now) < notInterestedLifetime }
    }
}
