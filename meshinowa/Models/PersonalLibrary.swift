import Foundation

enum PersonalLibrary {
    /// いいねしたお店とレビューしたお店をまとめる。いいねを外してもレビューのあるお店は残す。
    /// `wantToGo` は「行きたい」のお店（いいねなしの形）。いいね・レビューと重なるお店はそちらを使う。
    /// ID の付け方が違っても（Google の ID／店名と座標）、同じお店は1つにまとめる。
    static func restaurants(saved: [SavedRestaurant], reviews: [LocalReview],
                            wantToGo: [SavedRestaurant] = []) -> [SavedRestaurant] {
        var merged: [SavedRestaurant] = []
        for restaurant in saved where !merged.contains(where: { $0.isSameStore(as: restaurant) }) {
            merged.append(restaurant)
        }
        for review in reviews where !merged.contains(where: { $0.isSameStore(as: review.restaurant) }) {
            var restaurant = review.restaurant
            restaurant.isLiked = false
            merged.append(restaurant)
        }
        for restaurant in wantToGo where !merged.contains(where: { $0.isSameStore(as: restaurant) }) {
            merged.append(restaurant)
        }
        return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// お店ごとの自分の評価。キーは渡したお店の ID。ID の付け方が違っても同じお店のレビューを当てる。
    static func ratings(for restaurants: [SavedRestaurant], reviews: [LocalReview]) -> [String: Double] {
        var result: [String: Double] = [:]
        for restaurant in restaurants {
            if let review = reviews.first(where: { $0.restaurant.isSameStore(as: restaurant) }) {
                result[restaurant.id] = review.rating
            }
        }
        return result
    }

    /// レビューしたお店が持つ ID すべて。ID の付け方が違うお店とも照合できるようにする。
    static func reviewedKeys(_ reviews: [LocalReview]) -> Set<String> {
        reviews.reduce(into: Set<String>()) { $0.formUnion($1.restaurant.matchKeys) }
    }
}
