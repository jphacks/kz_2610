import GoogleMaps
import MapKit
import SwiftUI

/// 現在地や友達データを使わずに試せる、地図ホームの最初の実装。
struct MapHomeView: View {
    var showsSavedShortcut = true
    @EnvironmentObject private var saved: SavedRestaurantStore
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
        if result.id == selectedID { return 2 }
        return saved.restaurant(for: result.item) == nil && reviews.review(for: result.item) == nil ? 0 : 1
    }

    /// 地図に立てるピン。画面上で重なるものは優先度の低い方を隠し、拡大すると隠れていたお店が出てくる。
    /// 優先度は、選んだお店、自分の記録があるお店、検索で上位のお店の順。
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
        results.filter { genre.matches($0.item) }
    }

    /// 結果がまだないか、検索した範囲から地図が離れたときに再検索を勧める。
    private var suggestsAreaSearch: Bool {
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
            return GoogleMapPin(id: result.id.uuidString, title: result.item.name ?? "飲食店",
                                coordinate: result.item.placemark.coordinate,
                                symbol: Self.symbol(for: result.item),
                                genre: result.item.foodGenre,
                                mark: review.map { .reviewed($0.rating) } ?? (entry?.isLiked == true ? .liked : .none),
                                showsLikeBadge: review != nil && entry?.isLiked == true)
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
        .onChange(of: genre) { _, _ in
            selectedID = nil
            searchedRegion = nil
            adoptsNextCamera = false
            notice = visibleResults.isEmpty && !results.isEmpty ? "このジャンルのお店は見つかっていません" : nil
        }
        .onChange(of: visibleResults.map(\.id)) { _, _ in
            carouselItems = Self.nearestChain(visibleResults)
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
        // 知らせは数秒で消し、地図の Legal 表記を隠したままにしない。
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
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

    /// のれんを掛ける板を兼ねた検索欄。下側はのれんが付くので角を小さくする。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MeshinowaTheme.green)
                .accessibilityHidden(true)
            TextField("お店やジャンルを探す", text: $query)
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
                Text("件")
                    .font(MeshinowaFont.text(11, weight: .bold))
            }
            .foregroundStyle(MeshinowaTheme.mintInk)
            .padding(.horizontal, 11)
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
        .accessibilityLabel(isSearching ? "検索中" : "このエリアの\(genre.searchTerm)を検索")
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

    private func beginSearch(nearby: Bool = false) {
        let term = nearby ? genre.searchTerm : query.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
