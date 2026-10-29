import MapKit
import SwiftUI

struct SavedRestaurantsView: View {
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var friends: FriendStore
    @EnvironmentObject private var location: LocationStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @Environment(\.dismiss) private var dismiss
    var onFindRestaurants: (() -> Void)? = nil
    @State private var selected: SavedRestaurant?
    @State private var sort: SavedSort = .newest
    @State private var query = ""
    @State private var showsMap = false
    @State private var showsSearch = false
    @FocusState private var focusesSearch: Bool
    @State private var unreviewedOnly = false
    /// 上部の切り替え。保存の画面では「いいね」と「行きたい」だけを出す。
    @State private var collection: SavedCollection = .liked
    /// 「行きたい」（お店スワイプの右スワイプや地図の「行きたい」ボタンで入れたお店。いいねとは別）。
    @ObservedObject private var wantToGo = SwipeDiscoveryEntry.wantToGoStore
    @State private var wantToGoError: String?

    /// いいねしたお店とレビューしたお店と行きたいお店。
    private var library: [SavedRestaurant] {
        PersonalLibrary.restaurants(saved: saved.restaurants, reviews: reviews.reviews,
                                    wantToGo: wantToGoRestaurants.map { $0.restaurant })
    }

    /// 行きたいの元の記録と、保存画面で使う形の組。
    private var wantToGoRestaurants: [(entryID: String, restaurant: SavedRestaurant)] {
        wantToGo.entries.map { ($0.id, $0.savedRestaurant) }
    }

    private var wantToGoIDs: Set<String> {
        Set(wantToGoRestaurants.map { $0.restaurant.id })
    }

    private func count(of collection: SavedCollection) -> Int {
        library.filter { collection.includes($0, reviewed: Set(ratings.keys), wantToGo: wantToGoIDs) }.count
    }

    /// 一覧のお店ごとの自分の評価。キーは一覧のお店の ID。
    private var ratings: [String: Double] {
        PersonalLibrary.ratings(for: library, reviews: reviews.reviews)
    }

    private var visibleRestaurants: [SavedRestaurant] {
        SavedCollectionQuery.results(library, collection: collection, search: query, sort: sort, ratings: ratings,
                                     friendRatings: Dictionary(uniqueKeysWithValues: library.compactMap { entry in
                                         friends.summary(for: entry.mapItem).average.map { (entry.id, $0) }
                                     }),
                                     distances: Dictionary(uniqueKeysWithValues: library.compactMap { entry in
                                         location.location.map { (entry.id, $0.distance(from: CLLocation(latitude: entry.latitude, longitude: entry.longitude))) }
                                     }),
                                     unreviewedOnly: unreviewedOnly, wantToGo: wantToGoIDs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("保存").font(MeshinowaFont.wa(28, relativeTo: .largeTitle))
                    Spacer()
                    Button {
                        withAnimation(.snappy) { showsSearch.toggle() }
                        focusesSearch = showsSearch
                        if !showsSearch { query = "" }
                    } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("保存したお店を検索")
                    Button { withAnimation(.snappy) { showsMap.toggle() } } label: {
                        Image(systemName: showsMap ? "square.grid.2x2" : "map")
                    }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel(showsMap ? "一覧で表示" : "地図で表示")
                }
                .padding(.horizontal, 20)

                HStack(spacing: 4) {
                    ForEach(SavedCollection.allCases) { item in
                        let selected = collection == item
                        Button { collection = item } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.symbol)
                                Text(item.title)
                                Text("\(count(of: item))").font(MeshinowaFont.number(14))
                            }
                            .font(MeshinowaFont.text(14, weight: .bold))
                            .foregroundStyle(selected ? MeshinowaTheme.mintInk : MeshinowaTheme.bodyText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selected ? MeshinowaTheme.mint : MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                        .accessibilityValue("\(count(of: item))件")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MeshinowaTheme.hairline))
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                if showsSearch {
                    searchField
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                HStack(spacing: 8) {
                    Menu {
                        Picker("並び替え", selection: $sort) {
                            ForEach(SavedSort.allCases) { option in
                                Text(option.title).tag(option)
                                    .disabled(option == .friendRating && !friends.isAvailable)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) { Text(sort.title); Image(systemName: "chevron.down") }
                            .modifier(SavedFilterChip())
                    }
                    .accessibilityLabel("並び替え、\(sort.title)")
                    Button { unreviewedOnly.toggle() } label: {
                        Text("未レビューだけ").modifier(SavedFilterChip(isOn: unreviewedOnly))
                    }
                    .accessibilityAddTraits(unreviewedOnly ? .isSelected : [])
                    Spacer(minLength: 0)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 12)

                if sort == .distance, location.location == nil {
                    Text(location.error ?? "現在地を取得すると距離順で表示します。")
                        .font(MeshinowaFont.text(13)).padding(.horizontal, 20).padding(.top, 8)
                }

                if let error = saved.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(MeshinowaFont.text(14))
                        Button("再読み込み") { saved.reload() }
                            .buttonStyle(PaperButtonStyle(kind: .secondary))
                    }
                    .padding(20)
                }

                if visibleRestaurants.isEmpty && saved.errorMessage == nil {
                    emptyState
                        .padding(20)
                } else if showsMap {
                    SavedRestaurantMap(restaurants: visibleRestaurants, ratings: ratings) { selected = $0 }
                        .frame(height: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(20)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(visibleRestaurants) { restaurant in
                            Button { selected = restaurant } label: {
                                SavedGridCard(restaurant: restaurant, rating: ratings[restaurant.id])
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if restaurant.isLiked {
                                    Button("いいねから外す", systemImage: "heart.slash", role: .destructive) {
                                        _ = saved.setLiked(restaurant.mapItem, isLiked: false)
                                    }
                                }
                                if wantToGoIDs.contains(restaurant.id) {
                                    Button("行きたいから外す", systemImage: "flag.slash", role: .destructive) {
                                        removeFromWantToGo(restaurant)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }

            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: sort) { _, value in
            if value == .distance { location.request() }
        }
        .background(MeshinowaTheme.cream)
        .foregroundStyle(MeshinowaTheme.ink)
        .toolbar(onFindRestaurants == nil ? .visible : .hidden, for: .navigationBar)
        .sheet(item: $selected) { RestaurantInformationView(item: $0.mapItem) }
        // 行きたいはレビューを書いた（行った）ら外れる。サーバーとも同期する。
        .task { await SwipeDiscoveryEntry.refreshWantToGo(reviewedIDs: PersonalLibrary.reviewedKeys(reviews.reviews)) }
        .alert("行きたいを変更できませんでした", isPresented: Binding(get: { wantToGoError != nil },
                                                          set: { if !$0 { wantToGoError = nil } })) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(wantToGoError ?? "")
        }
    }

    private func removeFromWantToGo(_ restaurant: SavedRestaurant) {
        guard let entryID = wantToGoRestaurants.first(where: { $0.restaurant.id == restaurant.id })?.entryID else { return }
        do {
            try SwipeDiscoveryEntry.removeFromWantToGo(shopID: entryID)
        } catch {
            wantToGoError = (error as? LocalizedError)?.errorDescription ?? "もう一度お試しください。"
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            TextField("保存したお店を検索", text: $query)
                .font(MeshinowaFont.text(15))
                .submitLabel(.search)
                .focused($focusesSearch)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("検索を解除")
            }
        }
        .padding(.leading, 16)
        .frame(height: 44)
        .background(MeshinowaTheme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(MeshinowaTheme.hairline))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            // 空のお椀。和食のピンと同じ形。
            FoodGenreMark(genre: .washoku, size: 46)
                .frame(width: 80, height: 80)
                .background(MeshinowaTheme.mint, in: Circle())
            Text(!query.isEmpty ? "検索に一致するお店がありません" : (unreviewedOnly ? "未レビューのお店はありません" : "\(collection.title)のお店はまだありません"))
                .font(MeshinowaFont.heading(18))
            if query.isEmpty && !unreviewedOnly {
                Text(collection == .wantToGo
                     ? "お店スワイプで右にスワイプするか、マップのお店の「行きたい」を押すと、ここに集まります。"
                     : "マップでお店のハートを押すと、ここに集まります。")
                    .font(MeshinowaFont.text(14))
                    .foregroundStyle(MeshinowaTheme.bodyText)
            } else {
                Button("絞り込みを解除") { query = ""; unreviewedOnly = false }.buttonStyle(PaperButtonStyle(kind: .secondary))
            }
            Button("マップでお店を探す") {
                if let onFindRestaurants { onFindRestaurants() } else { dismiss() }
            }
            .buttonStyle(PaperButtonStyle())
            .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

extension SavedCollection: NorenTabItem {
    var symbol: String {
        switch self {
        case .liked: return "heart"
        case .wantToGo: return "flag"
        case .visited: return "star"
        }
    }
}

private struct SavedFilterChip: ViewModifier {
    var isOn = false
    func body(content: Content) -> some View {
        content.font(MeshinowaFont.text(13))
            .foregroundStyle(MeshinowaTheme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(isOn ? MeshinowaTheme.mint : MeshinowaTheme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? MeshinowaTheme.green : MeshinowaTheme.hairline, lineWidth: isOn ? 2 : 1))
    }
}

private struct SavedGridCard: View {
    let restaurant: SavedRestaurant
    let rating: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RestaurantPhotoView(item: restaurant.mapItem, imageHeight: 124)
                .overlay(alignment: .topLeading) {
                    GenreRibbon(genre: restaurant.foodGenre, compact: true).padding(.leading, 10)
                }
                .overlay(alignment: .topTrailing) {
                    if restaurant.isLiked {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(MeshinowaTheme.paper)
                            .frame(width: 26, height: 26)
                            .background(MeshinowaTheme.like, in: Circle())
                            .overlay(Circle().strokeBorder(MeshinowaTheme.paper, lineWidth: 2))
                            .padding(8)
                            .accessibilityLabel("いいね済み")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let rating { CompactRatingSeal(rating: rating).padding(.trailing, 8).offset(y: 70) }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(restaurant.name)
                    .font(MeshinowaFont.wa(15))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                Text(restaurant.address.restaurantArea)
                    .font(MeshinowaFont.text(11, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityHint("お店の詳細を開きます。長押しで保存から外せます")
    }
}

struct SavedRestaurantMap: View {
    let restaurants: [SavedRestaurant]
    /// レビューしたお店の自分の点数。レビュー済みは緑、いいねだけはピンクの印にする。
    var ratings: [String: Double] = [:]
    var onSelect: (SavedRestaurant) -> Void
    @State private var camera = GoogleMapPosition.fit([])
    @State private var selectedID: String?

    var body: some View {
        GoogleMapCanvas(position: camera, pins: restaurants.map { restaurant in
            GoogleMapPin(id: restaurant.id, title: restaurant.name,
                         coordinate: restaurant.mapItem.placemark.coordinate,
                         genre: restaurant.foodGenre,
                         mark: ratings[restaurant.id].map { .reviewed($0) } ?? (restaurant.isLiked ? .liked : .none))
        }, selectedID: $selectedID)
        .onAppear { camera = .fit(restaurants.map { $0.mapItem.placemark.coordinate }) }
        .onChange(of: restaurants.map(\.id)) { _, _ in
            camera = .fit(restaurants.map { $0.mapItem.placemark.coordinate })
        }
        .onChange(of: selectedID) { _, id in
            if let restaurant = restaurants.first(where: { $0.id == id }) {
                onSelect(restaurant)
                selectedID = nil
            }
        }
    }
}
