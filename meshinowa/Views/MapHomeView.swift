import GoogleMaps
import MapKit
import SwiftUI

/// 一般のお店と友達が評価したお店を一緒に表示し、友達のお店のピンを優先する地図。
struct MapHomeView: View {
    var showsSavedShortcut = true
    var isActive = true
    @EnvironmentObject private var friends: FriendStore
    @State private var searchesAllPlaces = true
    @State private var friendResults: [RestaurantSearchResult] = []
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var location: LocationStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @Environment(\.floatingTabBarSpace) private var tabBarSpace
    @Environment(\.reportsMapSelection) private var reportsMapSelection

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        latitudinalMeters: 2000, longitudinalMeters: 2000
    )

    @State private var camera: GoogleMapPosition = .region(initialRegion)
    @State private var visibleRegion = initialRegion
    /// 今の地図のカメラ。お店を追うときに拡大率を変えずに動かすのに使う。
    @State private var lastCamera: GMSCameraPosition?
    @State private var query = ""
    @State private var results: [RestaurantSearchResult] = []
    @State private var showsResults = false
    @State private var genre: RestaurantGenre = .all
    @State private var selectedID: UUID?
    @State private var isSearching = false
    /// 見つからなかったときなど、知らせたいことがあるときだけ出す。
    @State private var notice: String?
    /// 最後に検索した範囲。地図がここから動いたら「このエリアで検索」を出す。
    @State private var searchedRegion: MKCoordinateRegion?
    /// 検索結果や一覧に合わせて地図を動かしたあと、その範囲を検索済みとして扱う。
    @State private var adoptsNextCamera = false
    /// カードを横に並べる順番。隣のカードが地図上でも近いお店になるようにつなぐ。
    @State private var carouselItems: [RestaurantSearchResult] = []
    /// カルーセルで今見ているカード。ループのために同じお店を3周分並べ、何周目かも持つ。
    @State private var carouselPosition: CarouselSlot?
    /// 地図の大きさ。ピンが画面上で重なるかを測るのに使う。
    @State private var mapSize: CGSize = .zero
    @State private var cardHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

    private var pinOrder: [RestaurantSearchResult] {
        shownResults.sorted { rank($0) < rank($1) }
    }

    private func rank(_ result: RestaurantSearchResult) -> Int {
        RestaurantSearchResult.displayPriority(
            isSelected: result.id == selectedID,
            hasFriendRating: friends.summary(for: result.item).count > 0,
            hasPersonalRecord: saved.restaurant(for: result.item) != nil || reviews.review(for: result.item) != nil
        )
    }

    /// 地図に立てるピン。画面上で重なるものは優先度の低い方を隠し、拡大すると隠れていたお店が出てくる。
    /// 優先度は、選んだお店、友達の評価があるお店、自分の記録があるお店、検索で上位のお店の順。
    private var shownResults: [RestaurantSearchResult] {
        guard mapSize.width > 0 else { return visibleResults }
        let region = visibleRegion
        let left = region.center.longitude - region.span.longitudeDelta / 2
        let top = region.center.latitude + region.span.latitudeDelta / 2
        let ordered = visibleResults.enumerated().sorted { a, b in
            let pa = rank(a.element), pb = rank(b.element)
            return pa != pb ? pa > pb : a.offset < b.offset
        }
        var kept: [RestaurantSearchResult] = []
        var points: [CGPoint] = []
        for (_, result) in ordered {
            let c = result.item.placemark.coordinate
            let point = CGPoint(x: (c.longitude - left) / region.span.longitudeDelta * mapSize.width,
                                y: (top - c.latitude) / region.span.latitudeDelta * mapSize.height)
            // 画面の少し外までは描いておき、地図を少し動かしたときにピンが急に現れないようにする。
            let nearScreen = point.x > -mapSize.width * 0.3 && point.x < mapSize.width * 1.3
                && point.y > -mapSize.height * 0.3 && point.y < mapSize.height * 1.3
            guard result.id == selectedID || nearScreen else { continue }
            let overlaps = points.contains { hypot($0.x - point.x, $0.y - point.y) < 30 }
            guard result.id == selectedID || (!overlaps && kept.count < 60) else { continue }
            kept.append(result)
            points.append(point)
        }
        return kept
    }

    private var selectedResult: RestaurantSearchResult? {
        visibleResults.first { $0.id == selectedID }
    }

    private var visibleResults: [RestaurantSearchResult] {
        let recommendations = friendResults.filter {
            query.isEmpty || ($0.item.name ?? "").localizedStandardContains(query)
                || $0.item.restaurantCategory.localizedStandardContains(query)
        }
        let combined = searchesAllPlaces
            ? RestaurantSearchResult.merging(search: results, recommendations: recommendations)
            : recommendations
        return combined.filter { genre.matches($0.item) }
    }

    /// 結果がまだないか、検索した範囲から地図が離れたときに再検索を勧める。
    private var suggestsAreaSearch: Bool {
        guard searchesAllPlaces else { return false }
        guard !isSearching else { return true }
        guard let searchedRegion, !visibleResults.isEmpty else { return true }
        let center = visibleRegion.center, old = searchedRegion.center
        let span = visibleRegion.span, oldSpan = searchedRegion.span
        let moved = abs(center.latitude - old.latitude) > oldSpan.latitudeDelta * 0.25
            || abs(center.longitude - old.longitude) > oldSpan.longitudeDelta * 0.25
        let zoomed = span.latitudeDelta / oldSpan.latitudeDelta
        return moved || zoomed > 1.5 || zoomed < 0.5
    }

    var body: some View {
        GoogleMapCanvas(position: camera, pins: pinOrder.map { result in
            let entry = saved.restaurant(for: result.item)
            let review = reviews.review(for: result.item)
            let friendRating = friends.summary(for: result.item).average
            return GoogleMapPin(id: result.id.uuidString, title: result.item.name ?? "飲食店",
                                coordinate: result.item.placemark.coordinate,
                                symbol: Self.symbol(for: result.item),
                                genre: result.item.foodGenre,
                                // 自分の評価を優先し（からし色）、ない時だけ友達の平均点（緑）を出す。
                                mark: review.map { .reviewed($0.rating) } ?? friendRating.map { .friends($0) } ?? (entry?.isLiked == true ? .liked : .none),
                                showsLikeBadge: (review != nil || friendRating != nil) && entry?.isLiked == true)
        }, selectedID: Binding(get: { selectedID?.uuidString }, set: { selectedID = $0.flatMap(UUID.init(uuidString:)) }),
                        topPadding: headerHeight,
                        bottomPadding: tabBarSpace + (selectedResult == nil ? 0 : cardHeight)) { region, position in
            visibleRegion = region
            lastCamera = position
            if adoptsNextCamera {
                searchedRegion = region
                adoptsNextCamera = false
            }
        }
        // Extend the native map beneath the search panel, status area and floating tabs.
        // Keep overlays inside the safe area; only the map paints edge to edge.
        .ignoresSafeArea(.container)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { mapSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in mapSize = size }
            }
        }
        .task(id: isActive) {
            guard isActive else { return }
            if searchesAllPlaces && results.isEmpty && searchedRegion == nil && GooglePlacesService.isConfigured {
                beginSearch(nearby: true)
            }
            while !Task.isCancelled {
                await friends.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onChange(of: friendSnapshot, initial: true) { _, _ in
            // 同じお店が2つ来ても落ちないよう、先にあったものを使う。
            let previous = Dictionary(friendResults.map {
                (SavedRestaurant.identifier(for: $0.item), $0.id)
            }, uniquingKeysWith: { first, _ in first })
            let wasEmpty = friendResults.isEmpty
            friendResults = friends.dataset.ratedRestaurants.map {
                RestaurantSearchResult(id: previous[$0.id] ?? UUID(), item: $0.mapItem)
            }
            if !searchesAllPlaces && wasEmpty && !friendResults.isEmpty {
                camera = .fit(friendResults.map { $0.item.placemark.coordinate })
            }
        }
        .onChange(of: searchesAllPlaces) { _, _ in
            query = ""
            selectedID = nil
            notice = nil
            if !searchesAllPlaces && !friendResults.isEmpty {
                camera = .fit(friendResults.map { $0.item.placemark.coordinate })
            }
        }
        .onChange(of: genre) { _, _ in
            selectedID = nil
            searchedRegion = nil
            adoptsNextCamera = false
            notice = nil
            // 前のジャンルの結果だけでは判断せず、今の表示エリアで選んだジャンルを探し直す。
            beginSearch(nearby: true)
        }
        .onChange(of: visibleResults.map(\.id)) { _, _ in
            carouselItems = Self.nearestChain(visibleResults)
            if let selectedID, !visibleResults.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        }
        .onChange(of: selectedID) { _, id in
            reportsMapSelection?(selectedResult?.item)
            guard let id else { return }
            follow(id)
            // ピンから選んだときは、カードを真ん中の周に合わせる。
            if carouselPosition?.id != id { carouselPosition = CarouselSlot(lap: 1, id: id) }
        }
        .onChange(of: carouselPosition) { _, slot in
            if let slot, slot.id != selectedID { selectedID = slot.id }
        }
        .task(id: selectedID) {
            guard let index = carouselItems.firstIndex(where: { $0.id == selectedID }) else { return }
            await RestaurantPhotoStore.shared.prepareCarousel(items: carouselItems.map(\.item), selectedIndex: index)
        }
        // スワイプが止まってから、端の周にいれば真ん中の周の同じカードへ見た目を変えずに戻す。
        .task(id: carouselPosition) {
            guard let slot = carouselPosition, slot.lap != 1 else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { carouselPosition = CarouselSlot(lap: 1, id: slot.id) }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            searchHeader.background(GeometryReader { proxy in
                Color.clear.onAppear { headerHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in headerHeight = height }
            })
        }
        .overlay(alignment: .bottom) { bottomCard }
        // 現在地ボタンは、Google マップと同じく右下に置く。お店のカードが出ているときはその上。
        .overlay(alignment: .bottomTrailing) {
            locationButton
                .padding(.trailing, 14)
                .padding(.bottom, selectedResult == nil ? 16 : cardHeight + 6)
                .animation(.easeOut(duration: 0.2), value: selectedResult == nil)
        }
        // 知らせは数秒で消し、地図の Legal 表記を隠したままにしない。
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
        .onChange(of: location.location) { _, value in
            guard let value else { return }
            camera = .region(MKCoordinateRegion(center: value.coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000))
            searchedRegion = nil
        }
        .onChange(of: location.error) { _, value in if let value { notice = value } }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsResults) {
            SearchResultsView(results: visibleResults, filterDescription: genre.title) { result in
                selectedID = result.id
                adoptsNextCamera = true
                camera = .region(MKCoordinateRegion(
                    center: result.item.placemark.coordinate,
                    latitudinalMeters: 1000, longitudinalMeters: 1000
                ))
            }
        }
        .animation(.easeOut(duration: 0.2), value: selectedID)
        .animation(.snappy(duration: 0.25), value: suggestsAreaSearch)
        .animation(.snappy(duration: 0.25), value: notice)
    }

    static func symbol(for item: MKMapItem) -> String {
        switch item.pointOfInterestCategory {
        case .cafe: return "cup.and.saucer.fill"
        case .bakery: return "birthday.cake.fill"
        case .brewery: return "mug.fill"
        default: return "fork.knife"
        }
    }

    /// 地図の上に浮かぶ検索欄と、そこから垂れ下がるジャンルののれん。
    private var searchHeader: some View {
        VStack(spacing: 3) {
            searchField
            NorenTabs(items: RestaurantGenre.allCases, selection: $genre)
                .disabled(isSearching)
            if !searchesAllPlaces && visibleResults.isEmpty {
                Text(friendMapMessage)
                    .font(MeshinowaFont.text(13))
                    .foregroundStyle(MeshinowaTheme.bodyText)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            if suggestsAreaSearch {
                // のれんのすぐ下に重ねる。ボタンの高さは44pt。
                areaSearchButton
                    .offset(y: 50)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// 検索欄の右端に入れる、地図に出すお店の切り替え。「すべて」は友達の評価を優先して一般のお店も出す。
    private var scopeToggle: some View {
        HStack(spacing: 2) {
            scopeButton(title: "すべて", showsAll: true)
            scopeButton(title: "友達", showsAll: false)
        }
        .padding(3)
        .background(MeshinowaTheme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("地図に表示するお店")
    }

    private func scopeButton(title: String, showsAll: Bool) -> some View {
        let isSelected = searchesAllPlaces == showsAll
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { searchesAllPlaces = showsAll }
        } label: {
            Text(title)
                .font(MeshinowaFont.text(12, weight: .bold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? MeshinowaTheme.mintInk : MeshinowaTheme.secondaryText)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MeshinowaTheme.card)
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsAll ? "すべてのお店、友達の評価を優先" : "友達が評価したお店だけ")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var locationButton: some View {
        Button { location.request() } label: {
            Group {
                if location.isRequesting { ProgressView().controlSize(.small) }
                else { Image(systemName: "location.fill").font(.system(size: 17, weight: .semibold)) }
            }
            .foregroundStyle(MeshinowaTheme.green)
            .frame(width: 44, height: 44)
            .background(MeshinowaTheme.card, in: Circle())
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(location.isRequesting)
        .accessibilityLabel("現在地の周辺を探す")
    }

    /// のれんを掛ける板を兼ねた検索欄。下側はのれんが付くので角を小さくする。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MeshinowaTheme.green)
                .accessibilityHidden(true)
            TextField(searchesAllPlaces ? "お店を探す" : "友達のお店を絞り込む", text: $query)
                .font(MeshinowaFont.text(16))
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { beginSearch() }
                .disabled(isSearching)
                .accessibilityLabel("店名・ジャンルで検索")
            if !query.isEmpty && !isSearching {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                        .frame(width: 32, height: 44)
                }
                .accessibilityLabel("入力を消す")
            }
            scopeToggle
            if !visibleResults.isEmpty {
                listButton
            } else if showsSavedShortcut {
                NavigationLink {
                    SavedRestaurantsView()
                } label: {
                    Image(systemName: "heart")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MeshinowaTheme.mintInk)
                        .frame(width: 44, height: 36)
                        .background(Capsule().fill(MeshinowaTheme.mint))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存したお店、\(saved.restaurants.count)件")
            }
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(height: 50)
        .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6,
                                           bottomTrailingRadius: 6, topTrailingRadius: 18,
                                           style: .continuous)
            .fill(MeshinowaTheme.card)
            .shadow(color: .black.opacity(0.16), radius: 8, y: 2))
    }

    /// 結果の件数を兼ねた一覧ボタン。検索欄の右端に札のように置く。
    private var listButton: some View {
        Button { showsResults = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .bold))
                Text("\(visibleResults.count)")
                    .font(MeshinowaFont.number(15, relativeTo: .body))
            }
            .foregroundStyle(MeshinowaTheme.mintInk)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Capsule().fill(MeshinowaTheme.mint))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("検索結果\(visibleResults.count)件を一覧で見る")
    }

    /// 地図を動かしたときだけ出る、緑の再検索ボタン。ジャンルは上の切り替えで決まる。
    private var areaSearchButton: some View {
        Button { beginSearch(nearby: true) } label: {
            HStack(spacing: 6) {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "scope")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(isSearching ? "探しています…" : "このエリアで探す")
                    .font(MeshinowaFont.text(14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(MeshinowaTheme.green).shadow(color: .black.opacity(0.22), radius: 5, y: 2))
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // 検索中も薄くせず、そのまま進み具合を見せる。
        .allowsHitTesting(!isSearching)
        .accessibilityLabel(isSearching ? "検索中" : "このエリアの\(genre.searchTerm(for: query))を検索")
    }

    @ViewBuilder private var bottomCard: some View {
        if selectedResult != nil {
            carousel
                .padding(.bottom, 10)
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { cardHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in cardHeight = height }
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let notice {
            Text(notice)
                .font(MeshinowaFont.text(14, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(MeshinowaTheme.ink.opacity(0.88), in: Capsule())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// 横にスワイプしてお店を切り替えるカード。今見ているカードのお店がピンでも選ばれる。
    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                // お店が2軒以上なら3周分並べ、端まで行っても続けてスワイプできるようにする。
                ForEach(0..<(carouselItems.count > 1 ? 3 : 1), id: \.self) { lap in
                    ForEach(carouselItems) { result in
                        let slot = CarouselSlot(lap: carouselItems.count > 1 ? lap : 1, id: result.id)
                        RestaurantPreview(item: result.item, loadsPhoto: carouselPosition == slot)
                            .containerRelativeFrame(.horizontal) { width, _ in width - 40 }
                            .id(CarouselSlot(lap: carouselItems.count > 1 ? lap : 1, id: result.id))
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 10)
        }
        // 横スクロールは縦にも広がろうとするので、カードの高さに合わせて地図の下端に置く。
        .fixedSize(horizontal: false, vertical: true)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $carouselPosition)
        .onAppear {
            if let selectedID { carouselPosition = CarouselSlot(lap: 1, id: selectedID) }
        }
    }

    /// 選んだお店のピンがカードや上のパネルに隠れる位置にあれば、見える位置まで地図を動かす。
    private func follow(_ id: UUID) {
        guard let coordinate = visibleResults.first(where: { $0.id == id })?.item.placemark.coordinate else { return }
        let region = visibleRegion
        let x = (coordinate.longitude - (region.center.longitude - region.span.longitudeDelta / 2)) / region.span.longitudeDelta
        let y = ((region.center.latitude + region.span.latitudeDelta / 2) - coordinate.latitude) / region.span.latitudeDelta
        guard !(0.1...0.9).contains(x) || !(0.25...0.62).contains(y) else { return }
        adoptsNextCamera = searchedRegion != nil
        // ピンが画面の中ほどより少し上に来るようにする。拡大率と向きはそのまま。
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude - region.span.latitudeDelta * 0.08,
                                            longitude: coordinate.longitude)
        withAnimation(.easeInOut(duration: 0.35)) {
            if let lastCamera {
                camera = .camera(GMSCameraPosition(target: center, zoom: lastCamera.zoom,
                                                 bearing: lastCamera.bearing, viewingAngle: lastCamera.viewingAngle))
            } else {
                camera = .region(MKCoordinateRegion(center: center, span: region.span))
            }
        }
    }

    /// 西端のお店から始めて、まだ並べていない中でいちばん近いお店を順につなぐ。
    private static func nearestChain(_ items: [RestaurantSearchResult]) -> [RestaurantSearchResult] {
        var rest = items
        guard let start = rest.indices.min(by: {
            rest[$0].item.placemark.coordinate.longitude < rest[$1].item.placemark.coordinate.longitude
        }) else { return [] }
        var chain = [rest.remove(at: start)]
        while !rest.isEmpty {
            let last = chain[chain.count - 1].item.placemark.coordinate
            let next = rest.indices.min { a, b in
                let ca = rest[a].item.placemark.coordinate, cb = rest[b].item.placemark.coordinate
                return hypot(ca.latitude - last.latitude, ca.longitude - last.longitude)
                    < hypot(cb.latitude - last.latitude, cb.longitude - last.longitude)
            }!
            chain.append(rest.remove(at: next))
        }
        return chain
    }

    /// 評価の変更・削除や友達の解除に合わせて、検索に依存せずピンを更新する。
    private var friendSnapshot: [String] {
        friends.dataset.ratedRestaurants.map {
            "\($0.id)|\($0.name)|\($0.address)|\($0.category ?? "")|\($0.coordinate.latitude)|\($0.coordinate.longitude)"
        }
    }

    private var friendMapMessage: String {
        if !friends.isAvailable { return "友達の評価はまだ利用できません。「すべてのお店」でお店を探せます。" }
        if case .failed(let message) = friends.status { return message }
        if friends.status == .connecting { return "友達の評価を読み込んでいます…" }
        if friends.friends.isEmpty { return "「友達」タブでつながると、友達が評価したお店がこの地図に表示されます。" }
        return friendResults.isEmpty ? "友達が評価すると、この地図にお店が表示されます。" : "条件に合う友達のお店がありません。"
    }

    private func beginSearch(nearby: Bool = false) {
        guard searchesAllPlaces else { isSearchFocused = false; return }
        let term = genre.searchTerm(for: query)
        guard !isSearching, !term.isEmpty else { return }
        isSearchFocused = false
        isSearching = true
        selectedID = nil
        results = []
        notice = nil

        let region = visibleRegion
        let selectedGenre = genre
        Task { @MainActor in
            defer { isSearching = false }
            do {
                let found = try await GoogleRestaurantSearch.search(term: term, region: region,
                                                                    genre: selectedGenre, nearby: nearby)
                results = found.map { RestaurantSearchResult(item: $0) }
                searchedRegion = region
                if results.isEmpty {
                    notice = "お店が見つかりませんでした。地図を動かすか、言葉を変えてみてください"
                } else if !nearby {
                    adoptsNextCamera = true
                    camera = .fit(found.map { $0.placemark.coordinate })
                }
            } catch {
                notice = GooglePlacesService.isConfigured
                    ? "検索できませんでした。通信環境とGoogle Placesの設定を確認してください"
                    : "Google MapsのAPIキーを設定してください"
            }
        }
    }

}

private struct CarouselSlot: Hashable {
    let lap: Int
    let id: UUID
}

#Preview {
    NavigationStack { MapHomeView() }
        .preferredColorScheme(.light)
        .environmentObject(SavedRestaurantStore())
        .environmentObject(LocalReviewStore())
        .environmentObject(LocationStore())
        .environmentObject(FriendStore(backend: nil))
}
