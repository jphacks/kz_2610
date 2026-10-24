import Foundation
import CoreLocation

struct DemoFriend: Identifiable {
    let id: String
    let name: String
}

struct DemoRestaurant: Identifiable {
    let id: String
    let name: String
    let genre: String
    let coordinate: CLLocationCoordinate2D
}

struct DemoReview: Identifiable {
    let id: String
    let friendID: String
    let restaurantID: String
    let rating: Double
    let comment: String
    let updatedAt: Date
}

struct FriendRatingSummary {
    let reviews: [DemoReview]
    var count: Int { reviews.count }
    var average: Double? {
        guard !reviews.isEmpty else { return nil }
        return reviews.reduce(0) { $0 + $1.rating } / Double(reviews.count)
    }

    init(restaurantID: String, reviews: [DemoReview], friendIDs: Set<String>? = nil) {
        var latest: [String: DemoReview] = [:]
        for review in reviews where review.restaurantID == restaurantID {
            if let friendIDs, !friendIDs.contains(review.friendID) { continue }
            guard (1...5).contains(review.rating), review.rating * 2 == floor(review.rating * 2) else { continue }
            if let previous = latest[review.friendID], previous.updatedAt > review.updatedAt { continue }
            latest[review.friendID] = review
        }
        self.reviews = latest.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.friendID < $1.friendID
        }
    }
}

/// デモ専用。実在店舗の検索・保存データとは結合しない。
enum DemoRecommendations {
    static let favoriteFriendIDs: Set<String> = ["takuma", "saki", "mio"]
    static let friends = [
        DemoFriend(id: "takuma", name: "たくま"), DemoFriend(id: "yuki", name: "ゆうき"),
        DemoFriend(id: "ryo", name: "りょう"), DemoFriend(id: "saki", name: "さき"),
        DemoFriend(id: "haruto", name: "はると"), DemoFriend(id: "mio", name: "みお"),
        DemoFriend(id: "kenta", name: "けんた"), DemoFriend(id: "ayane", name: "あやね")
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

    static func summary(for restaurant: DemoRestaurant, friendIDs: Set<String>? = nil) -> FriendRatingSummary {
        FriendRatingSummary(restaurantID: restaurant.id, reviews: reviews, friendIDs: friendIDs)
    }

    static func friendName(_ id: String) -> String {
        friends.first { $0.id == id }?.name ?? "デモの友達"
    }

    private static func restaurant(_ id: String, _ name: String, _ genre: String,
                                   _ latitude: Double, _ longitude: Double) -> DemoRestaurant {
        DemoRestaurant(id: id, name: "【架空】\(name)", genre: genre,
                       coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    private static func review(_ id: String, _ friend: String, _ restaurant: String,
                              _ rating: Double, _ comment: String, _ time: Double) -> DemoReview {
        DemoReview(id: id, friendID: friend, restaurantID: restaurant,
                   rating: rating, comment: comment, updatedAt: Date(timeIntervalSince1970: time))
    }
}
