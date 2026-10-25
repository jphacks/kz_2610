import Foundation

enum SwipeDecisionKind: String, Codable, CaseIterable {
    case interested      // 気になる
    case notInterested   // イマイチ

    var title: String {
        switch self {
        case .interested: return "気になる"
        case .notInterested: return "イマイチ"
        }
    }
}

/// 1店舗に対する判断記録（判断時点の店舗情報を保存。写真は参照だけで複製しない）。
struct SwipeDecision: Identifiable, Codable, Hashable {
    var id: String { candidate.id }
    let candidate: SwipeCandidate
    var kind: SwipeDecisionKind
    var decidedAt: Date
}

/// 保存ファイルの中身。
struct SwipeDecisionFile: Codable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int = SwipeDecisionFile.currentSchemaVersion
    var decisions: [SwipeDecision]
}
