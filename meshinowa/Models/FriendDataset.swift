import CoreLocation
import Foundation
import MapKit

struct FriendProfile: Identifiable {
    let id: String
    let name: String
    var bio = ""
    var avatarSymbol = "person.fill"
}

struct FriendRestaurant: Identifiable {
    let id: String
    let name: String
    let genre: String
    let coordinate: CLLocationCoordinate2D
    var address = ""
    var category: String?
    var googlePlaceID: String?

    /// 実店舗の詳細・保存・レビューに渡すための MapKit 表現。
    var mapItem: MKMapItem {
        let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: ["Street": address])
        let item = MKMapItem(placemark: placemark)
        item.name = name
        if let googlePlaceID { item.googleDetails = GoogleRestaurantDetails(placeID: googlePlaceID) }
        item.pointOfInterestCategory = category.map(MKPointOfInterestCategory.init(rawValue:))
        return item
    }
}

struct FriendReview: Identifiable {
    let id: String
    let friendID: String
    let restaurantID: String
    let rating: Double
    let comment: String
    let updatedAt: Date
    var dish = ""
}

struct FriendRatingSummary {
    let reviews: [FriendReview]
    var count: Int { reviews.count }
    var average: Double? {
        guard !reviews.isEmpty else { return nil }
        return reviews.reduce(0) { $0 + $1.rating } / Double(reviews.count)
    }

    init(restaurantID: String, reviews: [FriendReview], friendIDs: Set<String>? = nil) {
        var latest: [String: FriendReview] = [:]
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

/// サーバーから取得した、友達のおすすめマップ・フィードが表示する一式。
struct FriendDataset {
    var friends: [FriendProfile]
    var favoriteFriendIDs: Set<String>
    var restaurants: [FriendRestaurant]
    var reviews: [FriendReview]

    /// 承認後の案内からは、その友達の実際の評価があるお店だけを表示する。
    func forFriend(_ friendID: String) -> FriendDataset {
        let scopedReviews = reviews.filter { $0.friendID == friendID }
        let restaurantIDs = Set(scopedReviews.map(\.restaurantID))
        var scoped = FriendDataset(friends: friends.filter { $0.id == friendID },
                                   favoriteFriendIDs: favoriteFriendIDs.intersection([friendID]),
                                   restaurants: restaurants.filter { restaurantIDs.contains($0.id) },
                                   reviews: scopedReviews)
        scoped.restaurants = scoped.ratedRestaurants
        return scoped
    }

    func summary(for restaurant: FriendRestaurant, friendIDs: Set<String>? = nil) -> FriendRatingSummary {
        FriendRatingSummary(restaurantID: restaurant.id, reviews: reviews, friendIDs: friendIDs)
    }

    /// 未評価や無効な評価のお店をおすすめ地図に混ぜない。
    var ratedRestaurants: [FriendRestaurant] {
        let friendIDs = Set(friends.map(\.id))
        return restaurants.filter { summary(for: $0, friendIDs: friendIDs).count > 0 }
    }

    func friendName(_ id: String) -> String {
        friends.first { $0.id == id }?.name ?? "友達"
    }

    func restaurant(_ id: String) -> FriendRestaurant? {
        restaurants.first { $0.id == id }
    }

    /// 1人1店の最新の評価だけを、新しい順に並べる。
    var latestReviews: [FriendReview] {
        reviews
            .filter { review in !reviews.contains { $0.friendID == review.friendID && $0.restaurantID == review.restaurantID && $0.updatedAt > review.updatedAt } }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 絞り込みに出すジャンル。お店に出てくる順で重複なし。
    var genres: [String] {
        restaurants.map(\.genre).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    func area(for restaurant: FriendRestaurant) -> String {
        let address = restaurant.address.withoutPostalCode.replacingOccurrences(of: "\n", with: " ")
        return address.isEmpty ? "住所の情報がありません" : address
    }
}
