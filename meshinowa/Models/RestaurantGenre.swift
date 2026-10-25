import MapKit

/// 地図のジャンル切り替え。ケースを足すと、のれんのタブにもそのまま並ぶ。
enum RestaurantGenre: String, CaseIterable, Identifiable, NorenTabItem {
    case all
    case restaurant
    case cafe
    case bakery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "すべて"
        case .restaurant: return "飲食店"
        case .cafe: return "カフェ"
        case .bakery: return "ベーカリー"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .bakery: return "birthday.cake.fill"
        }
    }

    var searchTerm: String { self == .restaurant ? "レストラン" : (self == .all ? "飲食店" : title) }

    var categories: [MKPointOfInterestCategory] {
        switch self {
        case .all: return [.restaurant, .cafe, .bakery, .brewery]
        case .restaurant: return [.restaurant]
        case .cafe: return [.cafe]
        case .bakery: return [.bakery]
        }
    }

    func matches(_ item: MKMapItem) -> Bool {
        guard self != .all else { return true }
        guard let category = item.pointOfInterestCategory else { return false }
        return categories.contains(category)
    }
}
