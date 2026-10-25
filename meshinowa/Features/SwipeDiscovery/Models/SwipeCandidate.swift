import Foundation

/// スワイプ対象の1店舗（友達レビューを店舗ごとにまとめたもの）。
struct SwipeCandidate: Identifiable, Codable, Hashable {
    let id: String                      // 店舗ID（友達レビューが指すID。既存の保存・レビューと同じID体系）
    let name: String
    let genre: String?                  // 詳細ジャンル（例：ラーメン）。大分類は SwipeCategory.classify(genre:) で決める
    let address: String?
    let latitude: Double
    let longitude: Double
    let reviews: [SwipeFriendReview]    // 新しい順。1件以上

    init(id: String, name: String, genre: String?, address: String?,
         latitude: Double, longitude: Double, reviews: [SwipeFriendReview]) {
        self.id = id
        self.name = name
        self.genre = genre
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.reviews = reviews.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    var averageRating: Double {
        guard !reviews.isEmpty else { return 0 }
        return reviews.map(\.rating).reduce(0, +) / Double(reviews.count)
    }

    /// いちばん新しいレビューの日時。平均評価が同じ時の並び順に使う。
    var latestReviewDate: Date {
        reviews.map(\.updatedAt).max() ?? .distantPast
    }

    /// カードに出す写真（新しいレビューのものから最大10枚）。
    var photos: [SwipeFriendPhoto] {
        Array(reviews.flatMap { review in
            review.photos.enumerated().map { SwipeFriendPhoto(source: $0.element, review: review, index: $0.offset) }
        }.prefix(10))
    }

    var category: SwipeCategory { SwipeCategory.classify(genre: genre) }

    /// 詳細ジャンルのタグ名（# なし）。大分類と同じ名前や不明な時は nil。
    var detailGenre: String? { SwipeCategory.detailGenre(for: genre) }

    /// 画面に出すジャンル名。MapKitのカテゴリ値は日本語に直す。
    var genreLabel: String { SwipeCategory.displayName(for: genre) }

    /// 最新のひとこと。
    var latestComment: String? {
        reviews.lazy.compactMap { $0.comment?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// 友達のおすすめ料理（新しい順、重複なし）。
    var recommendedDishes: [String] {
        var seen = Set<String>()
        return reviews.compactMap { $0.recommendedDish?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
