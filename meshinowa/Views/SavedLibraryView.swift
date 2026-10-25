import MapKit
import SwiftUI

struct SavedRestaurantsView: View {
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @Environment(\.dismiss) private var dismiss
    var onFindRestaurants: (() -> Void)? = nil
    @State private var selected: SavedRestaurant?
    @State private var collection: SavedCollection = .liked
    @State private var sort: SavedSort = .newest
    @State private var query = ""
    @State private var showsMap = false
    @State private var unreviewedOnly = false
    /// 「行きたい」（お店スワイプで右スワイプしたお店。いいねとは別）。
    @ObservedObject private var wantToGo = SwipeDiscoveryEntry.wantToGoStore
    @State private var wantToGoError: String?

    /// いいねしたお店とレビューしたお店と行きたいお店。行った＝レビューなので、いいねを外したお店も行ったに残る。
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

    private var ratings: [String: Double] {
        Dictionary(uniqueKeysWithValues: reviews.reviews.map { ($0.id, $0.rating) })
    }

    private var visibleRestaurants: [SavedRestaurant] {
        SavedCollectionQuery.results(library, collection: collection, search: query, sort: sort, ratings: ratings,
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

                UnderlineTabs(items: SavedCollection.allCases.map {
                    .init(value: $0, title: $0.title, badge: "\(count(of: $0))")
                }, selection: $collection)
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if collection == .liked {
                            Button { unreviewedOnly.toggle() } label: {
                                Label("未レビュー", systemImage: unreviewedOnly ? "checkmark" : "line.3.horizontal.decrease")
                            }
                            .buttonStyle(PillButtonStyle(isOn: unreviewedOnly))
                            .accessibilityAddTraits(unreviewedOnly ? .isSelected : [])
                        }
                        ForEach(SavedSort.allCases) { option in
                            Button(option.title) { sort = option }
                                .buttonStyle(PillButtonStyle(isOn: sort == option))
                                .accessibilityAddTraits(sort == option ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 14)

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
                .padding(.horizontal, 20)
                .padding(.top, 12)

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
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .toolbar(onFindRestaurants == nil ? .visible : .hidden, for: .navigationBar)
        .sheet(item: $selected) { RestaurantInformationView(item: $0.mapItem) }
        // 行きたいはレビューを書いた（行った）ら外れる。サーバーとも同期する。
        .task { await SwipeDiscoveryEntry.refreshWantToGo(reviewedIDs: Set(reviews.reviews.map(\.id))) }
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

    private func count(of collection: SavedCollection) -> Int {
        let reviewed = Set(ratings.keys)
        return library.filter { collection.includes($0, reviewed: reviewed, wantToGo: wantToGoIDs) }.count
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: collection == .visited ? "checkmark.circle" : (collection == .wantToGo ? "flag" : "heart"))
                .font(.system(size: 34))
                .foregroundStyle(MeshinowaTheme.green)
                .frame(width: 72, height: 72)
                .background(MeshinowaTheme.mint, in: Circle())
                .accessibilityHidden(true)
            Text(query.isEmpty ? "\(collection.title)のお店はまだありません" : "検索に一致するお店がありません")
                .font(MeshinowaFont.heading(18))
            if collection == .wantToGo && query.isEmpty {
                Text("友達タブの「お店スワイプ」で右にスワイプしたお店が入ります。")
                    .font(MeshinowaFont.text(14))
                    .foregroundStyle(MeshinowaTheme.bodyText)
            }
            if !query.isEmpty {
                Button("検索を解除") { query = "" }.buttonStyle(PaperButtonStyle(kind: .secondary))
            }
            Button("マップでお店を探す") {
                if let onFindRestaurants { onFindRestaurants() } else { dismiss() }
            }
            .buttonStyle(PaperButtonStyle())
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct SavedRow: View {
    let restaurant: SavedRestaurant
    let rating: Double?
    var isWantToGo = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name)
                    .font(MeshinowaFont.heading(17))
                    .lineLimit(2)
                Text(restaurant.address.withoutPostalCode)
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.bodyText)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if restaurant.isLiked { SoftTag(text: "いいね", tone: .like) }
                    if isWantToGo { SoftTag(text: "行きたい", tone: .mint) }

                    if let rating {
                        SoftTag(text: "自分 " + rating.formatted(.number.precision(.fractionLength(1))), tone: .mustard)
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MeshinowaTheme.outline)
                .padding(.top, 4)
                .accessibilityHidden(true)
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
