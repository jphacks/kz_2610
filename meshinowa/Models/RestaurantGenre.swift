import MapKit

/// 地図のジャンル切り替え。ケースを足すと、のれんのタブにもそのまま並ぶ。
/// 「すべて」と、ピンの器の形と同じ9つのジャンル。
enum RestaurantGenre: String, CaseIterable, Identifiable, NorenTabItem {
    case all
    case washoku, sushi, noodle, yakiniku, izakaya, yoshoku, chuka
    case cafe
    case bakery

    var id: String { rawValue }

    /// のれんに出す名前。
    var title: String { foodGenre?.title ?? "すべて" }

    /// ピンの器の形と同じジャンル。「すべて」は nil。
    var foodGenre: FoodGenre? {
        switch self {
        case .all: return nil
        case .washoku: return .washoku
        case .sushi: return .sushi
        case .noodle: return .noodle
        case .yakiniku: return .yakiniku
        case .izakaya: return .izakaya
        case .yoshoku: return .yoshoku
        case .chuka: return .chuka
        case .cafe: return .cafe
        case .bakery: return .bread
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .washoku: return "leaf.fill"
        case .sushi: return "fish.fill"
        case .noodle: return "fork.knife"
        case .yakiniku: return "flame.fill"
        case .izakaya: return "mug.fill"
        case .yoshoku: return "frying.pan.fill"
        case .chuka: return "takeoutbag.and.cup.and.straw.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .bakery: return "birthday.cake.fill"
        }
    }

    /// 「このエリアで探す」で使う言葉。
    var searchTerm: String {
        switch self {
        case .all: return "飲食店"
        case .washoku: return "和食"
        case .sushi: return "寿司"
        case .noodle: return "ラーメン"
        case .yakiniku: return "焼肉"
        case .izakaya: return "居酒屋"
        case .yoshoku: return "洋食"
        case .chuka: return "中華料理"
        case .cafe: return "カフェ"
        case .bakery: return "パン屋"
        }
    }

    /// 地図のカテゴリで大まかに絞る範囲。カフェとパン以外は飲食店として探す。
    var categories: [MKPointOfInterestCategory] {
        switch self {
        case .all: return [.restaurant, .cafe, .bakery, .brewery]
        case .cafe: return [.cafe]
        case .bakery: return [.bakery]
        default: return [.restaurant, .brewery, .winery]
        }
    }

    /// 取得済みのお店をこのジャンルで絞る。ジャンルはピンの形と同じ判定を使う。
    func matches(_ item: MKMapItem) -> Bool {
        guard let foodGenre else { return true }
        return item.foodGenre == foodGenre
    }
}
