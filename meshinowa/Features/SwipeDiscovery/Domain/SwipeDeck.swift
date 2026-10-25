import Foundation

/// まだ判断していない候補の待ち行列と、取り消し用の履歴。SwiftUI に依存しない。
struct SwipeDeck: Equatable {
    /// 先頭が画面最前面のカード。
    private(set) var queue: [SwipeCandidate]
    /// 確定した判断。末尾が直前の判断。
    private(set) var history: [SwipeDecision] = []

    init(candidates: [SwipeCandidate] = []) {
        queue = Self.unique(candidates)
    }

    var top: SwipeCandidate? { queue.first }
    var isEmpty: Bool { queue.isEmpty }
    var canUndo: Bool { !history.isEmpty }

    /// 描画するカード（最前面＋背面最大2枚）。
    func visible(limit: Int = 3) -> [SwipeCandidate] { Array(queue.prefix(limit)) }

    /// 先頭のカードを確定して履歴に積む。
    @discardableResult
    mutating func decide(_ kind: SwipeDecisionKind, at date: Date) -> SwipeDecision? {
        guard let top = queue.first else { return nil }
        queue.removeFirst()
        let decision = SwipeDecision(candidate: top, kind: kind, decidedAt: date)
        history.append(decision)
        return decision
    }

    /// 直前の判断を取り消し、そのカードを先頭に戻す。
    @discardableResult
    mutating func undo() -> SwipeDecision? {
        guard let last = history.popLast() else { return nil }
        queue.removeAll { $0.id == last.id }
        queue.insert(last.candidate, at: 0)
        return last
    }

    /// 履歴の末尾だけを見る（取り消し前の確認用）。
    var lastDecision: SwipeDecision? { history.last }

    /// デッキを作り直す。取り消し履歴は残し、履歴にある店は待ち行列に入れない。
    mutating func replaceQueue(with candidates: [SwipeCandidate]) {
        let decided = Set(history.map(\.id))
        queue = Self.unique(candidates).filter { !decided.contains($0.id) }
    }

    /// 整合チェックや一覧での変更で消えた記録を、取り消しの対象から外す。
    mutating func forget(ids: Set<String>) {
        history.removeAll { ids.contains($0.id) }
    }

    private static func unique(_ candidates: [SwipeCandidate]) -> [SwipeCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }
}
