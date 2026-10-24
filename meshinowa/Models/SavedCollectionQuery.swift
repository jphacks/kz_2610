import Foundation

enum SavedCollection: String, CaseIterable, Identifiable {
    case wantToGo, visited, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wantToGo: return "行きたい"
        case .visited: return "行った"
        case .favorites: return "お気に入り"
        }
    }
    func includes(_ restaurant: SavedRestaurant) -> Bool {
        switch self {
        case .wantToGo: return restaurant.status == .wantToGo
        case .visited: return restaurant.status == .visited
        case .favorites: return restaurant.isFavorite
        }
    }
}

enum SavedSort: String, CaseIterable, Identifiable {
    case newest, name, myRating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "保存した順"
        case .name: return "店名順"
        case .myRating: return "自分の評価順"
        }
    }
}

enum SavedCollectionQuery {
    static func results(_ restaurants: [SavedRestaurant], collection: SavedCollection, search: String,
                        sort: SavedSort, ratings: [String: Double]) -> [SavedRestaurant] {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return restaurants.filter {
            collection.includes($0) && (text.isEmpty || $0.name.localizedStandardContains(text) || $0.address.localizedStandardContains(text))
        }.sorted {
            switch sort {
            case .newest:
                if $0.savedAt != $1.savedAt { return $0.savedAt > $1.savedAt }
            case .name:
                if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .myRating:
                let left = ratings[$0.id] ?? -1, right = ratings[$1.id] ?? -1
                if left != right { return left > right }
            }
            return $0.id < $1.id
        }
    }
}
