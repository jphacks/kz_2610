import MapKit

/// 専用構成でだけ友達の評価を作る。店舗情報・写真・座標はGoogleの実データを使う。
enum PresentationDemo {
    struct Resolution {
        let dataset: FriendDataset
        let missingNames: [String]
    }

    enum DemoError: LocalizedError {
        case noStores
        var errorDescription: String? { "発表用の店舗情報をGoogleから取得できませんでした。通信とGoogle Placesの設定を確認し、友達画面を下に引いて再読み込みしてください。" }
    }

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

    /// 店舗が未取得の間は友達だけを用意し、位置や店舗名を仮データで補わない。
    static var dataset: FriendDataset? { makeDataset(places: [:]) }

    struct Target {
        let key: String
        let query: String
        let aliases: [[String]]

        func matches(_ item: MKMapItem) -> Bool {
            guard let name = item.name, item.googleDetails?.placeID.isEmpty == false else { return false }
            let normalized = name.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
                .filter { $0.isLetter || $0.isNumber }
            let matchesName = aliases.contains { words in words.allSatisfy { normalized.contains($0) } }
            let coordinate = item.placemark.coordinate
            let campus = initialRegion.center
            return matchesName && CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: campus.latitude, longitude: campus.longitude)) <= 2500
        }
    }

    static var targets: [Target] {
#if PRESENTATION_DEMO
        [
            Target(key: "champion", query: "カレーのチャンピオン 野々市本店 高橋町", aliases: [["チャンピオン", "本店"]]),
            Target(key: "higecho", query: "鬍鬚張魯肉飯 金沢工大前店 高橋町", aliases: [["鬍鬚張"], ["髭鬚張"], ["ひげちょう"], ["ひげ張"]]),
            Target(key: "hachiban", query: "8番らーめん 金沢工大前店 扇が丘", aliases: [["8番", "工大"]]),
            Target(key: "laterra", query: "ラテラ 金沢工業大学 21号館", aliases: [["ラテラ"], ["laterra"]]),
            Target(key: "misdo", query: "ミスタードーナツ 野々市ショップ 本町", aliases: [["ミスタードーナツ", "野々市"]])
        ]
#else
        []
#endif
    }

    /// 店舗名・住所・位置・Place IDを実際のGoogle検索から取得してから、友達の評価を結び付ける。
    @MainActor static func resolveStores(search: ((String) async throws -> [MKMapItem])? = nil) async throws -> Resolution {
        var places: [String: MKMapItem] = [:]
        var missing: [String] = []
        for target in targets {
            do {
                let results: [MKMapItem]
                if let search { results = try await search(target.query) }
                else {
                    results = try await GoogleRestaurantSearch.search(term: target.query, region: initialRegion,
                                                                     genre: .all, nearby: false)
                }
                if let item = results.first(where: target.matches) { places[target.key] = item }
                else { missing.append(target.query) }
            } catch { missing.append(target.query) }
        }
        guard !places.isEmpty, let dataset = makeDataset(places: places) else { throw DemoError.noStores }
        return Resolution(dataset: dataset, missingNames: missing)
    }

    /// 前の発表版が作った自分のサンプルだけを片付ける。手入力したレビューは残す。
    @MainActor static func removeLegacyPersonalSamples(saved: SavedRestaurantStore, reviews: LocalReviewStore) throws {
        guard isEnabled else { return }
        for review in reviews.reviews where review.comment == "発表用サンプル：友達とまた行きたいお店。" {
            try reviews.delete(id: review.id)
        }
        let seededNames: Set<String> = ["カレーのチャンピオン 野々市本店", "鬍鬚張魯肉飯 金沢工大前店", "8番らーめん 金沢工大前店"]
        for restaurant in saved.restaurants where seededNames.contains(restaurant.name) {
            guard saved.setLiked(restaurant.mapItem, isLiked: false) else { throw CocoaError(.fileWriteUnknown) }
        }
    }

    static func makeDataset(places: [String: MKMapItem]) -> FriendDataset? {
#if PRESENTATION_DEMO
        let friends = [FriendProfile(id: "demo-haru", name: "はる"), FriendProfile(id: "demo-yui", name: "ゆい"),
                       FriendProfile(id: "demo-sota", name: "そうた"), FriendProfile(id: "demo-mio", name: "みお"),
                       FriendProfile(id: "demo-ren", name: "れん"), FriendProfile(id: "demo-aoi", name: "あおい")]
        let entries: [(Int, String, Double, String)] = [
            (0, "champion", 5, "制作の合間に行くならここ！カツカレー推し。"),
            (1, "champion", 4.5, "午後の授業前に、友達とカレーを食べたい日に。"),
            (2, "champion", 4.5, "ハッカソンの昼休みにみんなで行きたい。"),
            (3, "higecho", 5, "今日は魯肉飯の気分。次はみんなで行こう！"),
            (0, "higecho", 4.5, "いつものランチを変えたい日に選びたい。"),
            (4, "higecho", 4, "制作がひと段落したら、ごはんに誘いたいお店。"),
            (2, "hachiban", 4.5, "研究室の帰りにらーめんを食べたい日に。"),
            (4, "hachiban", 4, "麺好きの友達と行く候補に入れたい！"),
            (1, "laterra", 4, "キャンパスでお昼を選ぶなら、まず学食から。"),
            (5, "laterra", 4.5, "次の授業までに、友達とお昼を食べる候補。"),
            (3, "misdo", 4.5, "発表練習のあとは、ドーナツでひと休みしたい。"),
            (5, "misdo", 4, "甘いもの好きの友達と寄りたい！")
        ]
        let verifiedPlaces = places.filter { key, item in
            targets.contains { $0.key == key && $0.matches(item) }
        }
        let shops = verifiedPlaces.mapValues { item in
            FriendRestaurant(id: SavedRestaurant.identifier(for: item), name: item.name ?? "飲食店", genre: item.foodGenre.title,
                             coordinate: item.placemark.coordinate, address: item.placemark.title?.withoutPostalCode ?? "",
                             category: item.pointOfInterestCategory?.rawValue, googleMapItem: item)
        }
        let now = Date()
        let reviews = entries.enumerated().compactMap { index, entry -> FriendReview? in
            let (friend, key, rating, comment) = entry
            guard let shop = shops[key] else { return nil }
            return FriendReview(id: "demo-review-\(index)", friendID: friends[friend].id, restaurantID: shop.id,
                                rating: rating, comment: comment, updatedAt: now.addingTimeInterval(-Double(index + 1) * 3600))
        }
        return FriendDataset(friends: friends, favoriteFriendIDs: [friends[0].id, friends[1].id],
                             restaurants: shops.values.sorted { $0.name < $1.name }, reviews: reviews)
#else
        nil
#endif
    }
}
