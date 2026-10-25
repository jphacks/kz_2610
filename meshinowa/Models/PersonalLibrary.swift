import Foundation

enum PersonalLibrary {
    /// いいねしたお店とレビューしたお店をまとめる。いいねを外してもレビューのあるお店は残す。
    static func restaurants(saved: [SavedRestaurant], reviews: [LocalReview]) -> [SavedRestaurant] {
        var merged = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        for review in reviews where merged[review.id] == nil {
            var restaurant = review.restaurant
            restaurant.isLiked = false
            merged[restaurant.id] = restaurant
        }
        return merged.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
