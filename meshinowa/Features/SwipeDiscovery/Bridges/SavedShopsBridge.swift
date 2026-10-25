import Foundation
import MapKit

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
    /// デモの架空の店は端末の「行きたい」にだけ入れ、サーバーには送らない。
    private let localOnly: Bool

    init(wantToGo: SwipeWantToGoStore, reviews: LocalReviewStore, localOnly: Bool = false) {
        self.wantToGo = wantToGo
        self.reviews = reviews
        self.localOnly = localOnly
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
        try wantToGo.add(candidate, localOnly: localOnly)
    }

    func removeFromWantToGo(shopID: String) throws {
        try wantToGo.remove(shopID: shopID)
    }

    private func isReviewed(_ shopID: String) -> Bool {
        reviews.reviews.contains { $0.id == shopID }
    }
}

extension SwipeWantToGoEntry {
    /// 既存の地図検索のお店（MKMapItem）から作る。店舗IDは既存の保存・レビューと同じ体系。
    init(item: MKMapItem, addedAt: Date = .now) {
        let coordinate = item.placemark.coordinate
        self.init(id: SavedRestaurant.identifier(for: item), name: item.name ?? "飲食店",
                  genre: item.pointOfInterestCategory?.rawValue, address: item.placemark.title,
                  latitude: coordinate.latitude, longitude: coordinate.longitude,
                  addedAt: addedAt, remoteRestaurantID: nil, isSynced: false)
    }

    static func shopID(for item: MKMapItem) -> String {
        SavedRestaurant.identifier(for: item)
    }

    /// 既存の保存画面に並べるための形（いいねは付けない）。店舗IDは既存と同じ店名＋座標の体系。
    var savedRestaurant: SavedRestaurant {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: ["Street": address ?? ""])
        let item = MKMapItem(placemark: placemark)
        item.name = name
        if let genre, genre.hasPrefix("MKPOICategory") {
            item.pointOfInterestCategory = MKPointOfInterestCategory(rawValue: genre)
        }
        return SavedRestaurant(item: item, savedAt: addedAt, isLiked: false)
    }
}
