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
                                     unreviewedOnly: collection == .liked && unreviewedOnly, wantToGo: wantToGoIDs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ScreenTitle(text: "保存")
                    Spacer()
                    Button { withAnimation(.snappy) { showsMap.toggle() } } label: {
                        Label(showsMap ? "一覧" : "地図", systemImage: showsMap ? "list.bullet" : "map")
                    }
                    .buttonStyle(PillButtonStyle(isOn: showsMap))
                    .accessibilityLabel(showsMap ? "一覧で表示" : "地図で表示")
                }
                .padding(.horizontal, 20)

                UnderlineTabs(items: [SavedCollection.liked, .wantToGo].map {
                    .init(value: $0, title: $0.title, badge: "\(count(of: $0))")
                }, selection: $collection)
                .padding(.horizontal, 20)

                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                // 件数と、絞り込み・並び替え。並び替えは1つのボタンにまとめ、横にはみ出さないようにする。
                HStack(spacing: 8) {
                    // 件数は上のタブに出ているので、ここには出さない。
                    Spacer(minLength: 0)
                    if collection == .liked {
                        Button { unreviewedOnly.toggle() } label: {
                            Label("未レビュー", systemImage: unreviewedOnly ? "checkmark" : "line.3.horizontal.decrease")
                        }
                        .buttonStyle(PillButtonStyle(isOn: unreviewedOnly))
                        .accessibilityAddTraits(unreviewedOnly ? .isSelected : [])
                    }
                    Menu {
                        Picker("並び替え", selection: $sort) {
                            ForEach(SavedSort.allCases) { option in
                                Text(option.title).tag(option)
                                    .disabled(option == .friendRating && !friends.isAvailable)
                            }
                        }
                    } label: {
                        Label(sort.title, systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(PillButtonStyle(isOn: true))
                    .accessibilityLabel("並び替え、\(sort.title)")
                }
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
                    LazyVStack(spacing: 0) {
                        ForEach(visibleRestaurants) { restaurant in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { selected = restaurant } label: {
                                    SavedRow(restaurant: restaurant,
                                             rating: reviews.review(for: restaurant.mapItem)?.rating,
                                             friends: friends.summary(for: restaurant.mapItem),
                                             isWantToGo: wantToGoIDs.contains(restaurant.id))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if wantToGoIDs.contains(restaurant.id) {
                                        Button("行きたいから外す", systemImage: "flag.slash", role: .destructive) {
                                            removeFromWantToGo(restaurant)
                                        }
                                    }
                                }
                                RestaurantPhotoView(item: restaurant.mapItem)
                            }
                            .padding(.bottom, 12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }

                Text("この端末に保存しています。\(visibleRestaurants.count)件を表示中。")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                    .padding(20)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: sort) { _, value in
            if value == .distance { location.request() }
        }
        .background(MeshinowaTheme.paper)
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
        .background(MeshinowaTheme.field, in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            // 空のお椀。和食のピンと同じ形。
            FoodGenreMark(genre: .washoku, size: 46)
                .frame(width: 80, height: 80)
                .background(MeshinowaTheme.mint, in: Circle())
            Text(query.isEmpty ? "\(collection.title)のお店はまだありません" : "検索に一致するお店がありません")
                .font(MeshinowaFont.heading(18))
            if query.isEmpty {
                Text(collection == .wantToGo
                     ? "お店スワイプで右にスワイプするか、マップのお店の「行きたい」を押すと、ここに集まります。"
                     : "マップでお店のハートを押すと、ここに集まります。")
                    .font(MeshinowaFont.text(14))
                    .foregroundStyle(MeshinowaTheme.bodyText)
            } else {
                Button("検索を解除") { query = "" }.buttonStyle(PaperButtonStyle(kind: .secondary))
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

/// 保存の一行。左の器はジャンルの形で、色は自分の記録（いいね＝ピンク、レビュー済み＝緑）。
/// 右には友達の評価（緑）と自分の評価（からし色）を分けて出す。
private struct SavedRow: View {
    let restaurant: SavedRestaurant
    let rating: Double?
    let friends: FriendRatingSummary
    var isWantToGo = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FoodGenreMark(genre: restaurant.foodGenre,
                          tone: rating != nil ? .reviewed : (restaurant.isLiked ? .liked : .plain), size: 34)
                .frame(width: 52, height: 52)
                .background(MeshinowaTheme.photo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name)
                    .font(MeshinowaFont.heading(17))
                    .lineLimit(2)
                Text(restaurant.address.withoutPostalCode)
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.bodyText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                if let rating {
                    MyRatingTag(rating: rating)
                } else if let average = friends.average {
                    RatingStamp(rating: average, friendCount: friends.count, size: 18)
                }
                HStack(spacing: 6) {
                    if isWantToGo {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(MeshinowaTheme.green)
                            .accessibilityLabel("行きたい")
                    }
                    if restaurant.isLiked {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(MeshinowaTheme.like)
                            .accessibilityLabel("いいね済み")
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("お店の情報を開きます")
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
