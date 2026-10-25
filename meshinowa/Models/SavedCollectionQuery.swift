import Foundation

enum SavedCollection: String, CaseIterable, Identifiable {
    case liked, visited
    var id: String { rawValue }
    var title: String {
        switch self {
        case .liked: return "いいね"
        case .visited: return "行った"
        }
    }
    /// 行った＝レビューしたお店。`reviewed` はレビューのあるお店のID。
    func includes(_ restaurant: SavedRestaurant, reviewed: Set<String>) -> Bool {
        switch self {
        case .liked: return restaurant.isLiked
        case .visited: return reviewed.contains(restaurant.id)
        }
    }
}

enum SavedSort: String, CaseIterable, Identifiable {
    case newest, name, myRating, friendRating, distance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "保存した順"
        case .name: return "店名順"
        case .myRating: return "自分の評価順"
        case .friendRating: return "友達の評価順"
        case .distance: return "距離順"
        }
    }
}

enum SavedCollectionQuery {
    static func results(_ restaurants: [SavedRestaurant], collection: SavedCollection, search: String,
                        sort: SavedSort, ratings: [String: Double], friendRatings: [String: Double] = [:], distances: [String: Double] = [:], unreviewedOnly: Bool = false) -> [SavedRestaurant] {
        let reviewed = Set(ratings.keys)
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return restaurants.filter {
            collection.includes($0, reviewed: reviewed) && !(unreviewedOnly && reviewed.contains($0.id))
                && (text.isEmpty || $0.name.localizedStandardContains(text) || $0.address.localizedStandardContains(text))
        }.sorted {
            switch sort {
            case .newest:
                if $0.savedAt != $1.savedAt { return $0.savedAt > $1.savedAt }
            case .name:
                if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .friendRating:
                let left = friendRatings[$0.id] ?? -1, right = friendRatings[$1.id] ?? -1
                if left != right { return left > right }
            case .distance:
                let left = distances[$0.id] ?? .infinity, right = distances[$1.id] ?? .infinity
                if left != right { return left < right }
            case .myRating:
                let left = ratings[$0.id] ?? -1, right = ratings[$1.id] ?? -1
                if left != right { return left > right }
            }
            return $0.id < $1.id
        }
    }
}
