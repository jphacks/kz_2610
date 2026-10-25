import MapKit

struct RestaurantSearchResult: Identifiable {
    let id: UUID
    let item: MKMapItem

    init(id: UUID = UUID(), item: MKMapItem) {
        self.id = id
        self.item = item
    }
    /// 友達のお店を先に並べ、検索で見つかった同じお店は詳しい店舗情報に差し替える。
    static func merging(search: [Self], recommendations: [Self]) -> [Self] {
        var searchByKey: [String: MKMapItem] = [:]
        for result in search {
            searchByKey[SavedRestaurant.identifier(for: result.item)] = result.item
        }
        var seen: Set<String> = []
        var merged: [Self] = []
        for result in recommendations + search {
            let key = SavedRestaurant.identifier(for: result.item)
            guard seen.insert(key).inserted else { continue }
            merged.append(Self(id: result.id, item: searchByKey[key] ?? result.item))
        }
        return merged
    }

    /// 選択したピンは常に残し、その次に友達の評価を優先する。
    static func displayPriority(isSelected: Bool, hasFriendRating: Bool, hasPersonalRecord: Bool) -> Int {
        if isSelected { return 3 }
        if hasFriendRating { return 2 }
        return hasPersonalRecord ? 1 : 0
    }

}
