@testable import meshinowa
import Foundation
import CoreLocation
import MapKit

/// 単体テスト専用。アプリ本体には含めない。
enum TestRecommendations {
    static let favoriteFriendIDs: Set<String> = ["takuma", "saki", "mio"]
    static let friends = [
        FriendProfile(id: "takuma", name: "たくま"), FriendProfile(id: "yuki", name: "ゆうき"),
        FriendProfile(id: "ryo", name: "りょう"), FriendProfile(id: "saki", name: "さき"),
        FriendProfile(id: "haruto", name: "はると"), FriendProfile(id: "mio", name: "みお"),
        FriendProfile(id: "kenta", name: "けんた"), FriendProfile(id: "ayane", name: "あやね")
    ]
    static let restaurants = [
        restaurant("diner", "こもれび食堂", "洋食", 35.6830, 139.7640),
        restaurant("cafe", "まるい喫茶室", "カフェ", 35.6800, 139.7620),
        restaurant("noodles", "めん処 ひだまり", "ラーメン", 35.6840, 139.7700),
        restaurant("bakery", "パン工房 つむぎ", "ベーカリー", 35.6770, 139.7660),
        restaurant("unrated", "夕凪キッチン", "洋食", 35.6800, 139.7720)
    ]
    static let reviews = [
        review("r1-old", "takuma", "diner", 3, "初めての訪問。", 1),
        review("r1", "takuma", "diner", 5, "デミグラスのオムライスが好き。", 10),
        review("r2", "yuki", "diner", 4.5, "ランチをゆっくり楽しめた。", 9),
        review("r3", "ryo", "diner", 4.5, "また友達と来たい。", 8),
        review("r4", "saki", "cafe", 5, "プリンとコーヒーの組み合わせが最高。", 7),
        review("r5", "mio", "cafe", 4, "読書したい日にぴったり。", 6),
        review("r6", "haruto", "noodles", 4.5, "スープがすっきりしていた。", 5),
        review("r7", "kenta", "noodles", 4, "細い麺が好みだった。", 4),
        review("r8", "ayane", "bakery", 5, "焼きたてのパンを買いたい。", 3),
        review("r9", "mio", "bakery", 4.5, "朝の散歩に寄りたいお店。", 2)
    ]

    static let dataset = FriendDataset(friends: friends, favoriteFriendIDs: favoriteFriendIDs,
                                       restaurants: restaurants, reviews: reviews)

    static func summary(for restaurant: FriendRestaurant, friendIDs: Set<String>? = nil) -> FriendRatingSummary {
        FriendRatingSummary(restaurantID: restaurant.id, reviews: reviews, friendIDs: friendIDs)
    }

    static func friendName(_ id: String) -> String {
        friends.first { $0.id == id }?.name ?? "デモの友達"
    }

    private static func restaurant(_ id: String, _ name: String, _ genre: String,
                                   _ latitude: Double, _ longitude: Double) -> FriendRestaurant {
        FriendRestaurant(id: id, name: "【架空】\(name)", genre: genre,
                       coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    private static func review(_ id: String, _ friend: String, _ restaurant: String,
                              _ rating: Double, _ comment: String, _ time: Double) -> FriendReview {
        FriendReview(id: id, friendID: friend, restaurantID: restaurant,
                   rating: rating, comment: comment, updatedAt: Date(timeIntervalSince1970: time))
    }
}
