import MapKit
import ObjectiveC

/// 地図のピンや一覧で、器の形で見せる9つのジャンル＋その他。
/// 形は output/wa-design/category-pins.html のデザインと同じ。
enum FoodGenre: String, CaseIterable, Identifiable {
    case washoku, sushi, noodle, yakiniku, izakaya, yoshoku, chuka, cafe, bread, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .washoku: return "和食"
        case .sushi: return "寿司"
        case .noodle: return "麺"
        case .yakiniku: return "焼肉"
        case .izakaya: return "居酒屋"
        case .yoshoku: return "洋食"
        case .chuka: return "中華"
        case .cafe: return "カフェ"
        case .bread: return "パン"
        case .other: return "その他"
        }
    }

    /// Google Places の種類から決める。店名から推測するより確か。
    private static let placeTypes: [(FoodGenre, [String])] = [
        (.sushi, ["sushi_restaurant", "seafood_restaurant"]),
        (.noodle, ["ramen_restaurant", "noodle_shop", "udon_noodle_shop", "soba_noodle_shop"]),
        (.yakiniku, ["yakiniku_restaurant", "barbecue_restaurant", "korean_barbecue_restaurant", "steak_house"]),
        (.izakaya, ["japanese_izakaya_restaurant", "yakitori_restaurant", "bar", "pub", "wine_bar", "bar_and_grill"]),
        (.washoku, ["japanese_restaurant", "tonkatsu_restaurant", "tempura_restaurant", "unagi_restaurant",
                    "shabu_shabu_restaurant", "japanese_curry_restaurant"]),
        (.yoshoku, ["italian_restaurant", "french_restaurant", "pizza_restaurant", "hamburger_restaurant",
                    "spanish_restaurant", "american_restaurant", "western_restaurant", "bistro", "steak_restaurant"]),
        (.chuka, ["chinese_restaurant", "korean_restaurant", "thai_restaurant", "indian_restaurant",
                  "vietnamese_restaurant", "asian_restaurant", "dumpling_restaurant"]),
        (.cafe, ["cafe", "coffee_shop", "dessert_shop", "ice_cream_shop", "tea_house", "confectionery"]),
        (.bread, ["bakery", "sandwich_shop"])
    ]

    /// 店名に含まれる言葉。先にあるものほど優先する。
    private static let keywords: [(FoodGenre, [String])] = [
        (.bread, ["ベーカリー", "パン", "bakery", "boulangerie"]),
        (.cafe, ["カフェ", "珈琲", "コーヒー", "喫茶", "cafe", "café", "coffee", "甘味", "パティスリー"]),
        (.sushi, ["寿司", "鮨", "すし", "鮮魚", "海鮮", "魚"]),
        (.noodle, ["ラーメン", "らーめん", "拉麺", "中華そば", "つけ麺", "めん処", "麺", "そば", "蕎麦", "うどん"]),
        (.yakiniku, ["焼肉", "ホルモン", "ステーキ", "肉"]),
        // 「バー」が「ハンバーガー」に当たらないよう、先にバーガーを洋食として見る。
        (.yoshoku, ["バーガー", "burger"]),
        (.izakaya, ["居酒屋", "酒場", "焼鳥", "焼き鳥", "やきとり", "串", "バー", "bar", "酒"]),
        (.chuka, ["中華", "餃子", "飯店", "韓国", "タイ料理", "カレー", "アジア"]),
        (.yoshoku, ["洋食", "イタリアン", "トラットリア", "ビストロ", "パスタ", "ピザ", "フレンチ", "ハンバーグ", "グリル"]),
        (.washoku, ["和食", "割烹", "食堂", "定食", "天ぷら", "天麩羅", "うなぎ", "とんかつ", "料亭"])
    ]

    /// 種類・店名・地図のカテゴリの順に見て決める。分からなければ「その他」。
    static func infer(name: String?, category: String?, placeTypes types: [String] = []) -> FoodGenre {
        let typeSet = Set(types)
        if let match = placeTypes.first(where: { !typeSet.isDisjoint(with: $0.1) }) { return match.0 }
        let lowered = (name ?? "").lowercased()
        if let match = keywords.first(where: { $0.1.contains { lowered.contains($0.lowercased()) } }) { return match.0 }
        switch category.map(MKPointOfInterestCategory.init(rawValue:)) {
        case .cafe?: return .cafe
        case .bakery?: return .bread
        case .brewery?, .winery?: return .izakaya
        default: return .other
        }
    }
}

private var searchedGenreKey: UInt8 = 0

extension MKMapItem {
    /// ジャンルを指定して検索したときの、そのジャンル。店名や種類からジャンルが分からないお店の手がかりにする。
    var searchedFoodGenre: FoodGenre? {
        get { (objc_getAssociatedObject(self, &searchedGenreKey) as? String).flatMap(FoodGenre.init(rawValue:)) }
        set { objc_setAssociatedObject(self, &searchedGenreKey, newValue?.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var foodGenre: FoodGenre {
        if let searchedFoodGenre { return searchedFoodGenre }
        let inferred = FoodGenre.infer(name: name, category: pointOfInterestCategory?.rawValue,
                                       placeTypes: googleDetails?.place?.types.map(\.rawValue) ?? [])
        return inferred == .other ? (searchedFoodGenre ?? .other) : inferred
    }
}

extension SavedRestaurant {
    var foodGenre: FoodGenre {
        PresentationDemo.foodGenreHint(for: id) ?? FoodGenre.infer(name: name, category: category)
    }
}
