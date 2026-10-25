import MapKit
import SwiftUI

/// タブバーの評価ボタンから開く「どのお店を評価する？」。
/// 選んだお店はいつもの評価シート（QuickRatingSheet）で記録し、保存と送信も今までと同じ流れを通る。
struct ReviewTargetPicker: View {
    var mapSelection: MKMapItem?
    var onSelect: (MKMapItem) -> Void
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchMessage: String?

    private static let defaultRegion = PresentationDemo.isEnabled ? PresentationDemo.initialRegion : MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        latitudinalMeters: 20_000, longitudinalMeters: 20_000
    )

    /// いいねしたけれど、まだ評価していないお店。
    private var likedUnreviewed: [SavedRestaurant] {
        let reviewed = Set(reviews.reviews.map(\.id))
        return saved.restaurants.filter { $0.isLiked && !reviewed.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    searchField
                    if let searchMessage {
                        Text(searchMessage)
                            .font(MeshinowaFont.text(13, relativeTo: .caption))
                            .foregroundStyle(MeshinowaTheme.secondaryText)
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                        row(item: item, detail: item.placemark.title?.withoutPostalCode)
                    }
                } footer: {
                    if results.isEmpty && mapSelection == nil && likedUnreviewed.isEmpty && reviews.reviews.isEmpty {
                        Text("店名で探すか、マップでお店を選んでから押してください。")
                    }
                }
                if let mapSelection {
                    Section("マップで選んでいるお店") {
                        row(item: mapSelection, detail: mapSelection.restaurantCategory)
                    }
                }
                if !likedUnreviewed.isEmpty {
                    Section("いいねして、まだ評価していないお店") {
                        ForEach(likedUnreviewed) { restaurant in
                            row(item: restaurant.mapItem, detail: restaurant.address.withoutPostalCode)
                        }
                    }
                }
                if !reviews.reviews.isEmpty {
                    Section("評価を変える") {
                        ForEach(Array(reviews.reviews.prefix(5))) { review in
                            row(item: review.restaurant.mapItem, detail: nil, rating: review.rating)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("どのお店を評価する？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MeshinowaTheme.green)
                .accessibilityHidden(true)
            TextField("店名で探す", text: $query)
                .font(MeshinowaFont.text(16))
                .submitLabel(.search)
                .onSubmit(search)
            if isSearching { ProgressView().controlSize(.small) }
        }
        .frame(minHeight: 44)
    }

    private func row(item: MKMapItem, detail: String?, rating: Double? = nil) -> some View {
        Button { onSelect(item) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "飲食店")
                        .font(MeshinowaFont.heading(16))
                        .foregroundStyle(MeshinowaTheme.ink)
                        .lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(MeshinowaFont.text(13, relativeTo: .caption))
                            .foregroundStyle(MeshinowaTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let rating {
                    MyRatingTag(rating: rating)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("このお店を評価します")
    }

    private func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !isSearching else { return }
        guard GooglePlacesService.isConfigured else {
            searchMessage = "店名で探すには、Google Places の設定が必要です。"
            return
        }
        isSearching = true
        searchMessage = nil
        let region = mapSelection.map {
            MKCoordinateRegion(center: $0.placemark.coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        } ?? Self.defaultRegion
        Task { @MainActor in
            defer { isSearching = false }
            do {
                results = try await GoogleRestaurantSearch.search(term: term, region: region, genre: .all, nearby: false)
                if results.isEmpty { searchMessage = "お店が見つかりませんでした。言葉を変えてみてください。" }
            } catch {
                results = []
                searchMessage = "検索できませんでした。通信環境を確認してください。"
            }
        }
    }
}

/// 自分の評価。からし色はアプリの中で自分の評価だけに使う。
struct MyRatingTag: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 3) {
            Text("自分")
                .font(MeshinowaFont.text(11, weight: .bold, relativeTo: .caption2))
            Text(rating, format: .number.precision(.fractionLength(1)))
                .font(MeshinowaFont.number(15, relativeTo: .body))
        }
        .foregroundStyle(MeshinowaTheme.mustardInk)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(MeshinowaTheme.mustardSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("自分の評価 \(rating.formatted(.number.precision(.fractionLength(1))))")
    }
}
