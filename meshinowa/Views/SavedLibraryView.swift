import MapKit
import SwiftUI

struct SavedRestaurantsView: View {
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @Environment(\.dismiss) private var dismiss
    var onFindRestaurants: (() -> Void)? = nil
    @State private var selected: SavedRestaurant?
    @State private var collection: SavedCollection = .wantToGo
    @State private var sort: SavedSort = .newest
    @State private var query = ""
    @State private var showsMap = false

    private var visibleRestaurants: [SavedRestaurant] {
        SavedCollectionQuery.results(saved.restaurants, collection: collection, search: query, sort: sort,
                                     ratings: Dictionary(uniqueKeysWithValues: reviews.reviews.map { ($0.id, $0.rating) }))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("コレクション", selection: $collection) {
                    ForEach(SavedCollection.allCases) { group in
                        Text("\(group.title) \(saved.restaurants.filter(group.includes).count)").tag(group)
                    }
                }
                .pickerStyle(.segmented)
                Picker("表示", selection: $showsMap) {
                    Text("一覧").tag(false)
                    Text("地図").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("並び順", selection: $sort) {
                    ForEach(SavedSort.allCases) { Text($0.title).tag($0) }
                }
                Text("この端末に保存しています。\(visibleRestaurants.count)件を表示中。")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)

                if let error = saved.errorMessage {
                    Text(error).font(MeshinowaFont.text(14))
                    Button("再読み込み") { saved.reload() }
                        .buttonStyle(PaperButtonStyle(kind: .secondary))
                }
                if visibleRestaurants.isEmpty && saved.errorMessage == nil {
                    emptyState
                } else if showsMap {
                    SavedRestaurantMap(restaurants: visibleRestaurants) { selected = $0 }
                        .frame(height: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .paperCard()
                } else {
                    ForEach(visibleRestaurants) { restaurant in
                        VStack(alignment: .leading, spacing: 12) {
                            Button { selected = restaurant } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(restaurant.name)
                                        .font(MeshinowaFont.text(18, weight: .black, relativeTo: .headline))
                                    Text(restaurant.address)
                                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                                        .foregroundStyle(MeshinowaTheme.secondaryText)
                                    if let rating = reviews.review(for: restaurant.mapItem)?.rating {
                                        Text("あなた ★ " + rating.formatted(.number.precision(.fractionLength(1))))
                                            .font(MeshinowaFont.text(14, weight: .bold))
                                    }
                                    Label("お店の情報を見る", systemImage: "chevron.right")
                                        .font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
                                        .foregroundStyle(MeshinowaTheme.green)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            RestaurantCollectionControls(item: restaurant.mapItem)
                        }
                        .padding(16)
                        .paperCard()
                    }
                }
            }
            .padding(20)
        }
        .searchable(text: $query, prompt: "保存したお店を検索")
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .navigationTitle("保存済み")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { RestaurantInformationView(item: $0.mapItem) }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "bookmark").font(.largeTitle).accessibilityHidden(true)
            Text(query.isEmpty ? "\(collection.title)のお店はまだありません" : "検索に一致するお店がありません")
                .font(MeshinowaFont.text(18, weight: .black, relativeTo: .headline))
            if !query.isEmpty {
                Button("検索を解除") { query = "" }.buttonStyle(PaperButtonStyle(kind: .secondary))
            }
            Button("マップでお店を探す") {
                if let onFindRestaurants { onFindRestaurants() } else { dismiss() }
            }
            .buttonStyle(PaperButtonStyle())
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .paperCard()
    }
}

struct SavedRestaurantMap: View {
    let restaurants: [SavedRestaurant]
    var onSelect: (SavedRestaurant) -> Void
    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedID: String?

    var body: some View {
        Map(position: $camera, selection: $selectedID) {
            ForEach(restaurants) { restaurant in
                Marker(restaurant.name, systemImage: "bookmark.fill", coordinate: restaurant.mapItem.placemark.coordinate)
                    .tint(MeshinowaTheme.green)
                    .tag(restaurant.id)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .onChange(of: restaurants.map(\.id)) { _, _ in camera = .automatic }
        .onChange(of: selectedID) { _, id in
            if let restaurant = restaurants.first(where: { $0.id == id }) {
                onSelect(restaurant)
                selectedID = nil
            }
        }
    }
}
