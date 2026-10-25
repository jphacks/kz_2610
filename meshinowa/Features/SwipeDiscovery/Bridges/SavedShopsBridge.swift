import Foundation

/// 新機能から既存の「行きたい・行った・自分のレビュー」を使う窓口。
///
/// 保存先を変える時は、このプロトコルに合わせた実装を作り、SwipeDiscoveryEnvironment.swift で差し替える。
@MainActor
protocol SavedShopsBridge: AnyObject {
    /// 保存先の画面での呼び名（例：「いいね」「行きたい」）。確認ダイアログなどに出す。
    var wantToGoTitle: String { get }
    /// 初めての右スワイプで出す短い知らせ。
    var savedNotice: String { get }
    /// デッキを作る前に呼ぶ（保存状態の整理・サーバーとの同期）。
    func prepare() async
    /// 行きたい・行った・自分のレビュー済みのどれかに入っていれば true。
    func isExcluded(shopID: String) -> Bool
    /// 右スワイプ確定時。失敗したら throw し、呼び出し側はカードを戻して判断を記録しない。
    func addToWantToGo(_ candidate: SwipeCandidate) throws
    /// 取り消し・判断の変更時。
    func removeFromWantToGo(shopID: String) throws
}

enum SwipeSavedShopsError: LocalizedError {
    case saveFailed(String?)
    case removeFailed(String?)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let message): return message ?? "保存できませんでした。もう一度お試しください。"
        case .removeFailed(let message): return message ?? "保存を外せませんでした。もう一度お試しください。"
        }
    }
}

/// 「行きたい」（いいねとは別。SwipeWantToGoStore に保存し Cloudflare と同期）と、
/// 既存の「行った」＝自分のレビュー済み（LocalReviewStore）を使う実装。既存の型は読むだけ。
@MainActor
final class WantToGoShopsBridge: SavedShopsBridge {
    private let wantToGo: SwipeWantToGoStore
    private let reviews: LocalReviewStore

    init(wantToGo: SwipeWantToGoStore, reviews: LocalReviewStore) {
        self.wantToGo = wantToGo
        self.reviews = reviews
    }

    let wantToGoTitle = "行きたい"
    let savedNotice = "行きたいに保存しました"

    func prepare() async {
        // 行きたいはレビューを書いた（行った）ら外れる。
        wantToGo.removeVisited(isReviewed: isReviewed)
        // デッキはサーバーを待たずに作る（同期は裏で行い、端末の一覧を正とする）。
        wantToGo.scheduleSync()
    }

    func isExcluded(shopID: String) -> Bool {
        wantToGo.contains(shopID) || isReviewed(shopID)
    }

    func addToWantToGo(_ candidate: SwipeCandidate) throws {
        try wantToGo.add(candidate)
    }

    func removeFromWantToGo(shopID: String) throws {
        try wantToGo.remove(shopID: shopID)
    }

    private func isReviewed(_ shopID: String) -> Bool {
        reviews.reviews.contains { $0.id == shopID }
    }
}

/// 架空のデモ用。デモの店は既存の保存一覧に入れず（既存のデモ方針）、新機能専用のキーにだけ覚える。
@MainActor
final class DemoSavedShopsBridge: SavedShopsBridge {
    static let storageKey = "swipeDiscovery.demoWantToGo"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    let wantToGoTitle = "デモの気になる"
    let savedNotice = "デモのお店なので、保存一覧には入りません"

    private var ids: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.storageKey) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Self.storageKey) }
    }

    func prepare() async {}
    func isExcluded(shopID: String) -> Bool { ids.contains(shopID) }
    func addToWantToGo(_ candidate: SwipeCandidate) throws { ids.insert(candidate.id) }
    func removeFromWantToGo(shopID: String) throws { ids.remove(shopID) }
}
