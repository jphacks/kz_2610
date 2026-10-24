import MapKit
import SwiftUI

struct DemoRecommendationsView: View {
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        latitudinalMeters: 1800, longitudinalMeters: 1800
    ))
    @State private var selectedID: String?
    @State private var detail: DemoRestaurant?

    private var selected: DemoRestaurant? {
        DemoRecommendations.restaurants.first { $0.id == selectedID }
    }

    var body: some View {
        Map(position: $camera, selection: $selectedID) {
            ForEach(DemoRecommendations.restaurants) { restaurant in
                Annotation(restaurant.name, coordinate: restaurant.coordinate) {
                    DemoRatingMarker(summary: DemoRecommendations.summary(for: restaurant))
                        .scaleEffect(selectedID == restaurant.id ? 1.15 : 1)
                }
                .tag(restaurant.id)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .top) {
            DemoNotice()
                .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            if let selected {
                preview(selected)
                    .padding(16)
            } else {
                Text("評価マーカーをタップして、友達のおすすめを見てみよう。")
                    .font(MeshinowaFont.text(14, weight: .bold))
                    .foregroundStyle(MeshinowaTheme.ink)
                    .padding(18)
                    .paperCard()
                    .padding(16)
            }
        }
        .navigationTitle("友達の評価デモ")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { restaurant in
            DemoRestaurantDetail(restaurant: restaurant, summary: DemoRecommendations.summary(for: restaurant))
        }
    }

    private func preview(_ restaurant: DemoRestaurant) -> some View {
        let summary = DemoRecommendations.summary(for: restaurant)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(restaurant.genre).font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
                    Text(restaurant.name).font(MeshinowaFont.text(20, weight: .black, relativeTo: .title2))
                }
                Spacer(minLength: 8)
                RatingStamp(rating: summary.average, friendCount: summary.count)
            }
            if let review = summary.reviews.first {
                DemoReviewRow(review: review)
            } else {
                Text("友達の評価はまだありません")
                    .font(MeshinowaFont.text(14))
            }
            Button("デモの詳細を見る") { detail = restaurant }
                .buttonStyle(PaperButtonStyle())
            Button("選択を解除") { selectedID = nil }
                .font(MeshinowaFont.text(14, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .padding(18)
        .paperCard(radius: 26, shadowOffset: 5)
    }
}

struct DemoNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEMO · 架空のおすすめマップ")
                .font(MeshinowaFont.text(14, weight: .black))
            Text("店舗・友達・レビューはすべて架空です。実際の店舗情報や保存一覧には反映されません。")
                .font(MeshinowaFont.text(12, relativeTo: .caption))
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .paperCard()
    }
}

private struct DemoRatingMarker: View {
    let summary: FriendRatingSummary

    var body: some View {
        VStack(spacing: 1) {
            if let average = summary.average {
                Text(average, format: .number.precision(.fractionLength(1)))
                    .font(MeshinowaFont.number(15, relativeTo: .body))
                Text("\(summary.count)人")
                    .font(MeshinowaFont.text(9, weight: .bold, relativeTo: .caption2))
            } else {
                Text("未評価")
                    .font(MeshinowaFont.text(11, weight: .bold, relativeTo: .caption))
            }
        }
        .foregroundStyle(summary.average == nil ? MeshinowaTheme.ink : MeshinowaTheme.card)
        .frame(minWidth: 48, minHeight: 48)
        .background(summary.average == nil ? MeshinowaTheme.card : MeshinowaTheme.green, in: Circle())
        .overlay(Circle().strokeBorder(MeshinowaTheme.ink, lineWidth: 2))
        .shadow(color: MeshinowaTheme.ink, radius: 0, x: 2, y: 2)
        .accessibilityElement(children: .combine)
    }
}

struct DemoRestaurantDetail: View {
    let restaurant: DemoRestaurant
    let summary: FriendRatingSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DemoNotice()
                    Text(restaurant.name)
                        .font(MeshinowaFont.text(26, weight: .black, relativeTo: .title))
                    HStack {
                        RatingStamp(rating: summary.average, friendCount: summary.count)
                        Text(summary.average == nil ? "友達の評価はまだありません" : "友達\(summary.count)人が評価")
                            .font(MeshinowaFont.text(17, weight: .black, relativeTo: .headline))
                    }
                    ForEach(summary.reviews) { review in
                        DemoReviewRow(review: review)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .paperCard()
                    }
                }
                .padding(20)
            }
            .background(MeshinowaTheme.paper)
            .foregroundStyle(MeshinowaTheme.ink)
            .navigationTitle("デモのお店")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct DemoReviewRow: View {
    let review: DemoReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(DemoRecommendations.friendName(review.friendID))
                Text("★ " + review.rating.formatted(.number.precision(.fractionLength(1))))
            }
            .font(MeshinowaFont.text(14, weight: .black))
            Text("「\(review.comment)」")
                .font(MeshinowaFont.text(14))
        }
    }
}
