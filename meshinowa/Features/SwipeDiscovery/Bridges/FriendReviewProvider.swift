import CoreLocation
import Foundation
import MapKit

/// 既存の Friend Lens と同じ考え方を、新機能側の型として持つ（対応付けはアダプタで）。
enum SwipeFriendLens: Hashable {
    case all
    case favorites
    case selected(Set<String>)   // 友達ID

    var title: String {
        switch self {
        case .all: return "友達全員"
        case .favorites: return "お気に入りの友達"
        case .selected(let ids): return "\(ids.count)人を選択"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: return "友達全員"
        case .favorites: return "お気に入り"
        case .selected(let ids): return "\(ids.count)人を選択"
        }
    }
}

/// Friend Lens の選択画面に出す友達。
struct SwipeFriendProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let isFavorite: Bool
}

/// 候補の取得元。今は既存の友達データ（サーバー接続時は実データ、未接続は Friend Lens のデモ）、
/// 将来は Supabase などの実装に差し替える。
protocol FriendReviewProvider {
    /// 架空のデモデータなら true。保存先や表示の切り替えに使う。
    var isDemo: Bool { get }

    /// 友達レビューを店舗ごとにまとめた候補。距離での絞り込みは SwipeDeckBuilder が行う。
    func candidates(near center: CLLocationCoordinate2D,
                    radius: CLLocationDistance,
                    lens: SwipeFriendLens) async throws -> [SwipeCandidate]

    /// Friend Lens で選べる友達。
    func friends() async -> [SwipeFriendProfile]
}

/// 既存の FriendDataset（FriendStore の実データ／DemoRecommendations のデモ）を読むだけのアダプタ。
/// 既存データには手を入れず、ここで新機能の型に変換する。
struct FriendDatasetReviewProvider: FriendReviewProvider {
    let isDemo: Bool
    private let dataset: @MainActor () -> FriendDataset
    private let mapItems: SwipeMapItemRegistry

    init(isDemo: Bool, mapItems: SwipeMapItemRegistry, dataset: @escaping @MainActor () -> FriendDataset) {
        self.isDemo = isDemo
        self.mapItems = mapItems
        self.dataset = dataset
    }

    func candidates(near center: CLLocationCoordinate2D, radius: CLLocationDistance,
                    lens: SwipeFriendLens) async throws -> [SwipeCandidate] {
        let data = await dataset()
        let includedIDs = Self.friendLens(lens).includedFriendIDs(friends: data.friends, favorites: data.favoriteFriendIDs)
        var candidates: [SwipeCandidate] = []
        for restaurant in data.restaurants {
            // 1人1店の最新評価だけ（既存の集計と同じルール）。
            let summary = data.summary(for: restaurant, friendIDs: includedIDs)
            guard summary.count > 0 else { continue }
            let reviews = summary.reviews.map { review in
                SwipeFriendReview(
                    id: review.id, friendID: review.friendID, friendName: data.friendName(review.friendID),
                    rating: review.rating,
                    comment: review.comment.isEmpty ? nil : review.comment,
                    recommendedDish: review.dish.isEmpty ? nil : review.dish,
                    updatedAt: review.updatedAt)
            }
            let item = restaurant.mapItem
            // 店舗IDは既存の保存・レビューと同じ体系（店名＋丸めた座標）。実データは externalKey がそれにあたる。
            let id = isDemo ? SavedRestaurant.identifier(for: item) : restaurant.id
            let address = data.area(for: restaurant)
            candidates.append(SwipeCandidate(
                id: id, name: restaurant.name,
                // 実データのジャンルは MapKit のカテゴリ値から作られているので、その値のまま渡す（詳細タグを出さない）。
                genre: restaurant.category ?? restaurant.genre,
                address: address,
                latitude: restaurant.coordinate.latitude, longitude: restaurant.coordinate.longitude,
                reviews: reviews))
            await mapItems.register(id: id, item: item)
        }
        return candidates
    }

    func friends() async -> [SwipeFriendProfile] {
        let data = await dataset()
        return data.friends.map {
            SwipeFriendProfile(id: $0.id, name: $0.name, isFavorite: data.favoriteFriendIDs.contains($0.id))
        }
    }

    private static func friendLens(_ lens: SwipeFriendLens) -> FriendLens {
        switch lens {
        case .all: return FriendLens(mode: .allFriends)
        case .favorites: return FriendLens(mode: .favoriteFriends)
        case .selected(let ids): return FriendLens(mode: .selectedFriends, selectedFriendIDs: ids)
        }
    }
}

/// 候補ごとの MKMapItem を覚えておく。写真の検索で見つかった Google の Place ID を、
/// 保存でも使い回すため（MKMapItem は参照型で、写真の取得時に Place ID が書き込まれる）。
@MainActor
final class SwipeMapItemRegistry {
    private var items: [String: MKMapItem] = [:]

    func register(id: String, item: MKMapItem) {
        if items[id] == nil { items[id] = item }
    }

    func item(for candidate: SwipeCandidate) -> MKMapItem {
        if let item = items[candidate.id] { return item }
        let coordinate = CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude)
        let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: ["Street": candidate.address ?? ""])
        let item = MKMapItem(placemark: placemark)
        item.name = candidate.name
        if let genre = candidate.genre, genre.hasPrefix("MKPOICategory") {
            item.pointOfInterestCategory = MKPointOfInterestCategory(rawValue: genre)
        }
        items[candidate.id] = item
        return item
    }
}
