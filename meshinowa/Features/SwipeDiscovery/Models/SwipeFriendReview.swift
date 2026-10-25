import Foundation

/// 友達1人の1店舗へのレビュー。
struct SwipeFriendReview: Identifiable, Codable, Hashable {
    let id: String
    let friendID: String
    let friendName: String
    let friendIcon: SwipePhotoSource?
    let rating: Double                  // 1.0〜5.0
    let comment: String?                // ひとこと
    let recommendedDish: String?
    let visitedAt: Date?
    /// レビューを書いた（更新した）日時。並び順（F-03）と「新しい順」に使う。
    let updatedAt: Date
    let photos: [SwipePhotoSource]      // 最大5枚（既存レビューと同じ上限）

    init(id: String, friendID: String, friendName: String, friendIcon: SwipePhotoSource? = nil,
         rating: Double, comment: String? = nil, recommendedDish: String? = nil,
         visitedAt: Date? = nil, updatedAt: Date, photos: [SwipePhotoSource] = []) {
        self.id = id
        self.friendID = friendID
        self.friendName = friendName
        self.friendIcon = friendIcon
        self.rating = rating
        self.comment = comment
        self.recommendedDish = recommendedDish
        self.visitedAt = visitedAt
        self.updatedAt = updatedAt
        self.photos = Array(photos.prefix(5))
    }
}

/// 写真の参照先。デモはアセット、既存の端末内写真はファイル、将来はリモート。
enum SwipePhotoSource: Codable, Hashable {
    case asset(name: String)
    case file(URL)
    case remote(URL)
}

/// カードに出す1枚の写真と、その投稿者。
struct SwipeFriendPhoto: Hashable, Identifiable {
    let source: SwipePhotoSource
    let review: SwipeFriendReview       // 投稿者の名前・星を出すため
    let index: Int

    var id: String { "\(review.id)#\(index)" }
}
