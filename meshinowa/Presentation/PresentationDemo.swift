import MapKit

/// 専用のビルド構成でだけ有効になる、金沢工大での発表データ。
/// 通常のDebug/Releaseでは店舗・友達・レビューの定義ごとコンパイルしない。
enum PresentationDemo {
    static var isEnabled: Bool {
#if PRESENTATION_DEMO
        true
#else
        false
#endif
    }

    static var initialRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.5302, longitude: 136.6255),
                           latitudinalMeters: 1800, longitudinalMeters: 1800)
    }

    static var dataset: FriendDataset? {
#if PRESENTATION_DEMO
        makeDataset()
#else
        nil
#endif
    }

    static var restaurants: [FriendRestaurant] {
#if PRESENTATION_DEMO
        shops
#else
        []
#endif
    }

    static func foodGenreHint(for restaurantID: String) -> FoodGenre? {
        restaurants.first { $0.id == restaurantID }?.foodGenreHint
    }

    /// 別アプリの保存領域にだけ、自分の記録の初期サンプルを用意する。
    @MainActor static func seedPersonalRecords(saved: SavedRestaurantStore, reviews: LocalReviewStore) throws {
        guard isEnabled else { return }
        for shop in restaurants.prefix(3) where !saved.contains(shop.mapItem) {
            guard saved.setLiked(shop.mapItem, isLiked: true) else { throw CocoaError(.fileWriteUnknown) }
        }
        for (index, shop) in restaurants.prefix(2).enumerated() where reviews.review(for: shop.mapItem) == nil {
            try reviews.save(item: shop.mapItem, rating: index == 0 ? 4.5 : 4,
                             comment: "発表用サンプル：友達とまた行きたいお店。", wantAgain: true)
        }
    }

    /// 検索も固定した候補から返し、発表中に外部サービスの応答で内容が変わらないようにする。
    static func search(term: String, region: MKCoordinateRegion, genre: RestaurantGenre, nearby: Bool) -> [MKMapItem] {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        return restaurants.filter { shop in
            let coordinate = shop.coordinate
            let inArea = abs(coordinate.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
                && abs(coordinate.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
            let matchesText = query.isEmpty || query == "飲食店" || query == genre.searchTerm
                || "\(shop.name) \(shop.genre) \(shop.address)".localizedStandardContains(query)
            return (!nearby || inArea) && matchesText && genre.matches(shop.mapItem)
        }.map(\.mapItem)
    }

#if PRESENTATION_DEMO
    // 店名・住所は公式情報、位置は2026-10-25の公開地図検索で確認。学食2軒は同じ21号館。
    private static let shops: [FriendRestaurant] = [
        shop("カレーのチャンピオン 野々市本店", "洋食", .yoshoku, 36.53024, 136.6247454, "高橋町20-17"),
        shop("鬍鬚張魯肉飯 金沢工大前店", "中華", .chuka, 36.5300798, 136.6253378, "高橋町20-5"),
        shop("8番らーめん 金沢工大前店", "麺", .noodle, 36.5277215, 136.6295995, "扇が丘445"),
        shop("Restaurant LA TERRA・ラテラ", "和食", .washoku, 36.5299588, 136.6292489, "扇が丘7-1 金沢工業大学21号館"),
        shop("Cafeteria IL SOLE・イルソーレ", "洋食", .yoshoku, 36.5299588, 136.6292489, "扇が丘7-1 金沢工業大学21号館2階"),
        shop("ミスタードーナツ 野々市ショップ", "カフェ", .cafe, 36.5330353, 136.6119705, "本町4丁目6-20")
    ]

    private static func shop(_ name: String, _ genre: String, _ hint: FoodGenre, _ latitude: Double,
                             _ longitude: Double, _ address: String) -> FriendRestaurant {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = name
        return FriendRestaurant(id: SavedRestaurant.identifier(for: item), name: name, genre: genre,
                                coordinate: item.placemark.coordinate, address: "石川県野々市市" + address,
                                category: (hint == .cafe ? MKPointOfInterestCategory.cafe : .restaurant).rawValue,
                                foodGenreHint: hint)
    }

    private static func makeDataset() -> FriendDataset {
        let friends = [FriendProfile(id: "demo-haru", name: "はる"), FriendProfile(id: "demo-yui", name: "ゆい"),
                       FriendProfile(id: "demo-sota", name: "そうた"), FriendProfile(id: "demo-mio", name: "みお"),
                       FriendProfile(id: "demo-ren", name: "れん"), FriendProfile(id: "demo-aoi", name: "あおい")]
        let entries: [(Int, Int, Double, String, String)] = [
            (0, 0, 5, "制作の合間に行くならここ！カツカレー推し。", "Lカツカレー"),
            (1, 0, 4.5, "午後の授業前に、友達とカレーを食べたい日に。", "カツカレー"),
            (2, 0, 4.5, "ハッカソンの昼休みにみんなで行きたい。", "カツカレー"),
            (3, 1, 5, "今日は魯肉飯の気分。次はみんなで行こう！", "魯肉飯"),
            (0, 1, 4.5, "いつものランチを変えたい日に選びたい。", "魯肉飯"),
            (4, 1, 4, "制作がひと段落したら、ごはんに誘いたいお店。", "招牌飯"),
            (2, 2, 4.5, "研究室の帰りにらーめんを食べたい日に。", "野菜らーめん"),
            (4, 2, 4, "麺好きの友達と行く候補に入れたい！", "野菜らーめん"),
            (1, 3, 4, "キャンパスでお昼を選ぶなら、まず学食から。", "日替わりメニュー"),
            (5, 3, 4.5, "次の授業までに、友達とお昼を食べる候補。", "日替わりメニュー"),
            (3, 5, 4.5, "発表練習のあとは、ドーナツでひと休みしたい。", "ドーナツ"),
            (5, 5, 4, "甘いもの好きの友達と寄りたい！", "ドーナツ")
        ]
        // 起動するたびに相対時刻を作り直し、発表日にも古いフィードに見えないようにする。
        let now = Date()
        let reviews = entries.enumerated().map { index, entry in
            let (friend, shop, rating, comment, dish) = entry
            return FriendReview(id: "demo-review-\(index)", friendID: friends[friend].id, restaurantID: shops[shop].id,
                                rating: rating, comment: comment, updatedAt: now.addingTimeInterval(-Double(index + 1) * 3600), dish: dish)
        }
        return FriendDataset(friends: friends, favoriteFriendIDs: [friends[0].id, friends[1].id],
                             restaurants: shops.filter { shop in reviews.contains { $0.restaurantID == shop.id } }, reviews: reviews)
    }
#endif
}
