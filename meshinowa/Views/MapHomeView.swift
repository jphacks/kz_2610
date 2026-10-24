import MapKit
import SwiftUI

/// 現在地や友達データを使わずに試せる、地図ホームの最初の実装。
struct MapHomeView: View {
    @EnvironmentObject private var saved: SavedRestaurantStore
    private struct SearchResult: Identifiable {
        let id = UUID()
        let item: MKMapItem
    }

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        latitudinalMeters: 2000, longitudinalMeters: 2000
    )

    @State private var camera: MapCameraPosition = .region(initialRegion)
    @State private var visibleRegion = initialRegion
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selectedID: UUID?
    @State private var isSearching = false
    @State private var message = "東京駅周辺から表示しています。地図を動かして、店名やジャンルで検索できます。"
    @FocusState private var isSearchFocused: Bool

    private var selectedResult: SearchResult? {
        results.first { $0.id == selectedID }
    }

    var body: some View {
        Map(position: $camera, selection: $selectedID) {
            ForEach(results) { result in
                Marker(result.item.name ?? "飲食店",
                       systemImage: saved.contains(result.item) ? "bookmark.fill" : "fork.knife",
                       coordinate: result.item.placemark.coordinate)
                    .tint(saved.contains(result.item) ? MeshinowaTheme.accent : MeshinowaTheme.green)
                    .tag(result.id)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .safeAreaInset(edge: .top) { searchHeader }
        .safeAreaInset(edge: .bottom) { bottomCard }
        .navigationTitle("マップ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(MeshinowaTheme.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SavedRestaurantsView()
                } label: {
                    Label("保存", systemImage: "bookmark")
                }
                .accessibilityLabel("保存したお店、\(saved.restaurants.count)件")
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .accessibilityHidden(true)
            TextField("店名・ジャンルで検索", text: $query)
                .font(MeshinowaFont.text(15))
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { beginSearch() }
                .disabled(isSearching)
                .accessibilityLabel("店名・ジャンル")
            Button {
                beginSearch()
            } label: {
                Image(systemName: "arrow.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("お店を検索")
            .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .paperCard(radius: 22)
        .padding(16)
    }

    @ViewBuilder private var bottomCard: some View {
        if let result = selectedResult {
            RestaurantPreview(item: result.item) { selectedID = nil }
                .id(result.id)
                .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(isSearching ? "お店を探しています" : "お店を探そう")
                        .font(MeshinowaFont.text(17, weight: .black, relativeTo: .headline))
                    if isSearching { ProgressView() }
                }
                Text(message)
                    .font(MeshinowaFont.text(14))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                Button("このエリアの飲食店を検索") {
                    beginSearch(nearby: true)
                }
                .buttonStyle(PaperButtonStyle())
                .disabled(isSearching)
            }
            .foregroundStyle(MeshinowaTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .paperCard()
            .padding(16)
        }
    }

    private func beginSearch(nearby: Bool = false) {
        let term = nearby ? "飲食店" : query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSearching, !term.isEmpty else { return }
        isSearchFocused = false
        isSearching = true
        selectedID = nil
        results = []
        message = "検索が終わるまでお待ちください。"

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        request.region = visibleRegion
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .brewery])

        Task { @MainActor in
            defer { isSearching = false }
            do {
                let response = try await MKLocalSearch(request: request).start()
                results = response.mapItems.map { SearchResult(item: $0) }
                if results.isEmpty {
                    message = "条件に合うお店が見つかりませんでした。検索語やエリアを変えてみてください。"
                } else {
                    camera = .region(response.boundingRegion)
                    message = "\(results.count)件見つかりました。マーカーをタップすると店名と住所を確認できます。"
                }
            } catch {
                message = "検索できませんでした。通信環境を確認して、もう一度お試しください。"
            }
        }
    }
}

#Preview {
    NavigationStack { MapHomeView() }
        .preferredColorScheme(.light)
        .environmentObject(SavedRestaurantStore())
}
