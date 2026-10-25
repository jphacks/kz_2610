import Foundation

enum PersonalLibrary {
    /// いいねしたお店とレビューしたお店をまとめる。いいねを外してもレビューのあるお店は残す。
    /// `wantToGo` は「行きたい」のお店（いいねなしの形）。いいね・レビューと重なるお店はそちらを使う。
    static func restaurants(saved: [SavedRestaurant], reviews: [LocalReview],
                            wantToGo: [SavedRestaurant] = []) -> [SavedRestaurant] {
        var merged = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        for review in reviews where merged[review.id] == nil {
            var restaurant = review.restaurant
            restaurant.isLiked = false
            merged[restaurant.id] = restaurant
        }
        for restaurant in wantToGo where merged[restaurant.id] == nil {
            merged[restaurant.id] = restaurant
        }
        return merged.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
