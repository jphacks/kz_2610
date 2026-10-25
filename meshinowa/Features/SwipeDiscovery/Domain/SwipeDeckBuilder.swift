import Foundation

/// 距離での絞り込み・除外・並べ替えを行い、デッキの並びを作る。画面や取得元に依存しない。
enum SwipeDeckBuilder {
    struct Result: Equatable {
        /// デッキに入れる候補（F-03 の順）。
        let candidates: [SwipeCandidate]
        /// 半径内にある友達レビュー付きの店の数（除外前）。0 なら「近くに友達のレビューがない」。
        let inRadiusCount: Int
    }

    static func build(from candidates: [SwipeCandidate],
                      centerLatitude: Double, centerLongitude: Double, radius: Double,
                      category: SwipeCategory? = nil,
                      decidedIDs: Set<String>,
                      isExcluded: (String) -> Bool) -> Result {
        var seen = Set<String>()
        let inRadius = candidates.filter { candidate in
            guard !candidate.reviews.isEmpty, seen.insert(candidate.id).inserted else { return false }
            return distance(fromLatitude: centerLatitude, longitude: centerLongitude,
                            toLatitude: candidate.latitude, longitude: candidate.longitude) <= radius
        }
        let inCategory = inRadius.filter { category == nil || $0.category == category }
        let remaining = inCategory.filter { !decidedIDs.contains($0.id) && !isExcluded($0.id) }
        return Result(candidates: remaining.sorted(by: isOrderedBefore), inRadiusCount: inCategory.count)
    }

    /// F-03：友達の平均評価が高い順、同じならレビューが新しい順。最後は店舗IDで固定する。
    static func isOrderedBefore(_ a: SwipeCandidate, _ b: SwipeCandidate) -> Bool {
        let left = (a.averageRating * 1000).rounded(), right = (b.averageRating * 1000).rounded()
        if left != right { return left > right }
        if a.latestReviewDate != b.latestReviewDate { return a.latestReviewDate > b.latestReviewDate }
        return a.id < b.id
    }

    /// 2点間の直線距離（メートル、球面近似）。
    static func distance(fromLatitude lat1: Double, longitude lon1: Double,
                         toLatitude lat2: Double, longitude lon2: Double) -> Double {
        let radius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
