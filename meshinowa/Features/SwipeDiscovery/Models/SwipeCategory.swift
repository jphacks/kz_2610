import Foundation

/// 地図のジャンル別ピン（output/wa-design/category-pins.html）と同じ「9つ＋その他」の大分類。
/// IDも category-pins.html とそろえ、地図のピンとカードのタグで同じ区分になるようにする。
enum SwipeCategory: String, CaseIterable, Codable, Identifiable {
    case washoku, sushi, noodle, yakiniku, izakaya, yoshoku, chuka, cafe, pan, other

    var id: String { rawValue }

    /// # を付けない名前（読み上げ・絞り込みで使う）。
    var name: String {
        switch self {
        case .washoku: return "和食"
        case .sushi: return "寿司・海鮮"
        case .noodle: return "麺"
        case .yakiniku: return "焼肉・肉"
        case .izakaya: return "居酒屋・バー"
        case .yoshoku: return "洋食・イタリアン"
        case .chuka: return "中華・アジア"
        case .cafe: return "カフェ・スイーツ"
        case .pan: return "パン"
        case .other: return "その他"
        }
    }

    /// "#和食" など。
    var tagName: String { "#" + name }

    /// 含める詳細ジャンル。
    var genres: [String] {
        switch self {
        case .washoku: return ["和食", "日本料理", "天ぷら", "うなぎ", "とんかつ", "しゃぶしゃぶ", "料理旅館", "沖縄料理", "食堂"]
        case .sushi: return ["寿司", "海鮮"]
        case .noodle: return ["ラーメン", "そば", "うどん"]
        case .yakiniku: return ["焼肉", "ホルモン", "ステーキ", "ハンバーグ"]
        case .izakaya: return ["居酒屋", "焼き鳥", "串揚げ", "もつ鍋", "鍋", "バー", "お酒", "お好み焼き", "もんじゃ焼き"]
        case .yoshoku: return ["洋食", "イタリアン", "フレンチ", "パスタ", "ピザ", "スペイン料理", "ビストロ", "ハンバーガー"]
        case .chuka: return ["中華料理", "餃子", "韓国料理", "タイ料理", "カレー"]
        case .cafe: return ["カフェ", "喫茶店", "スイーツ", "ケーキ", "タピオカ"]
        case .pan: return ["パン", "サンドイッチ"]
        case .other: return ["ビュッフェ"]
        }
    }

    /// MapKit のカテゴリ値（生の値と、既存画面が出す日本語名）の対応。
    /// これに当たる時は詳細ジャンルが分からないので、詳細タグは出さない。
    private static let mapKitValues: [String: (category: SwipeCategory, label: String)] = [
        "MKPOICategoryCafe": (.cafe, "カフェ"),
        "MKPOICategoryBakery": (.pan, "ベーカリー"),
        "MKPOICategoryBrewery": (.izakaya, "ブルワリー"),
        "MKPOICategoryWinery": (.izakaya, "ワイナリー"),
        "MKPOICategoryNightlife": (.izakaya, "ナイトライフ"),
        "MKPOICategoryRestaurant": (.other, "飲食店"),
        "MKPOICategoryFoodMarket": (.other, "食料品店"),
        "ベーカリー": (.pan, "ベーカリー"),
        "ブルワリー": (.izakaya, "ブルワリー"),
        "ワイナリー": (.izakaya, "ワイナリー"),
        "ナイトライフ": (.izakaya, "ナイトライフ"),
        "飲食店": (.other, "飲食店"),
        "レストラン": (.other, "飲食店")
    ]

    /// 部分一致は長い語から調べる（「ハンバーグ」を「バー」より先に見る）。
    private static let wordsByLength: [(word: String, category: SwipeCategory)] = allCases
        .flatMap { category in category.genres.map { (word: $0, category: category) } }
        .sorted { $0.word.count != $1.word.count ? $0.word.count > $1.word.count : $0.word < $1.word }

    private static func normalized(_ genre: String?) -> String? {
        guard let value = genre?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func isMapKitValue(_ genre: String?) -> Bool {
        guard let value = normalized(genre) else { return false }
        return mapKitValues[value] != nil
    }

    /// 1. 完全一致 → 2. 含む語 → 3. MapKit の値 → 4. その他。分類できなくても候補からは消さない。
    static func classify(genre: String?) -> SwipeCategory {
        guard let value = normalized(genre) else { return .other }
        if let mapped = mapKitValues[value] { return mapped.category }
        if let exact = allCases.first(where: { $0.genres.contains(value) }) { return exact }
        let folded = value.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
        if let partial = wordsByLength.first(where: { folded.contains($0.word) }) { return partial.category }
        return .other
    }

    /// 詳細ジャンルのタグ名（# なし）。不明・MapKit値・大分類と同じ名前の時は nil。
    static func detailGenre(for genre: String?) -> String? {
        guard let value = normalized(genre), mapKitValues[value] == nil else { return nil }
        let category = classify(genre: value)
        guard value != category.name else { return nil }
        return value
    }

    /// 詳細シートなどに出すジャンル名。
    static func displayName(for genre: String?) -> String {
        guard let value = normalized(genre) else { return "ジャンル不明" }
        return mapKitValues[value]?.label ?? value
    }
}
