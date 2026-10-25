import SwiftUI

struct ProfileView: View {
    var onFindRestaurants: () -> Void
    @EnvironmentObject private var reviews: LocalReviewStore
    @EnvironmentObject private var saved: SavedRestaurantStore
    @State private var editing: LocalReview?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 64))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("あなたの記録")
                            .font(MeshinowaFont.text(26, weight: .black, relativeTo: .title))
                        Text("この端末のプロフィール")
                            .font(MeshinowaFont.text(12, relativeTo: .caption))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    statistic("レビュー", count: reviews.reviews.count)
                    statistic("行った", count: reviews.reviews.count)
                    statistic("いいね", count: saved.restaurants.filter(\.isLiked).count)
                }
                .padding(18)
                .paperCard()

                NavigationLink {
                    MyReviewsView(onFindRestaurants: onFindRestaurants)
                } label: { Label("自分のレビュー一覧", systemImage: "text.bubble") }
                    .buttonStyle(PaperButtonStyle())
                NavigationLink {
                    MyRestaurantMapView(onFindRestaurants: onFindRestaurants)
                } label: { Label("マイマップ", systemImage: "map") }
                    .buttonStyle(PaperButtonStyle(kind: .secondary))

                if let error = reviews.loadError {
                    Text(error).font(MeshinowaFont.text(14))
                    Button("レビューを再読み込み") { reviews.reload() }
                }
                Text("最近のレビュー")
                    .font(MeshinowaFont.text(20, weight: .black, relativeTo: .title2))
                if reviews.reviews.isEmpty && reviews.loadError == nil {
                    Text("まだレビューがありません。お店の詳細から星だけでも記録できます。")
                        .font(MeshinowaFont.text(14))
                }
                ForEach(Array(reviews.reviews.prefix(3))) { review in
                    LocalReviewRow(review: review) { editing = review }
                }
                Text("ログイン・アカウント設定は準備中です。記録は友達に公開されず、アプリを削除すると端末内のデータも消えます。")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .navigationTitle("プロフィール")
        .sheet(item: $editing) { ReviewEditor(item: $0.restaurant.mapItem, existing: $0) }
    }

    private func statistic(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(MeshinowaFont.text(15, weight: .bold))
            Spacer()
            Text("\(count)件").font(MeshinowaFont.number(20))
        }
    }
}

struct MyReviewsView: View {
    var onFindRestaurants: () -> Void
    @EnvironmentObject private var reviews: LocalReviewStore
    @State private var editing: LocalReview?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let error = reviews.loadError {
                    Text(error).font(MeshinowaFont.text(14))
                    Button("再読み込み") { reviews.reload() }
                } else if reviews.reviews.isEmpty {
                    Text("自分のレビューはまだありません")
                        .font(MeshinowaFont.text(20, weight: .black, relativeTo: .title2))
                    Button("マップでお店を探す", action: onFindRestaurants)
                        .buttonStyle(PaperButtonStyle())
                }
                ForEach(reviews.reviews) { review in
                    LocalReviewRow(review: review) { editing = review }
                }
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .navigationTitle("自分のレビュー")
        .sheet(item: $editing) { ReviewEditor(item: $0.restaurant.mapItem, existing: $0) }
    }
}

private struct LocalReviewRow: View {
    let review: LocalReview
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 10) {
                Text(review.restaurant.name)
                    .font(MeshinowaFont.text(18, weight: .black, relativeTo: .headline))
                Text("あなた ★ " + review.rating.formatted(.number.precision(.fractionLength(1))))
                    .font(MeshinowaFont.text(15, weight: .black))
                if !review.comment.isEmpty { Text(review.comment).font(MeshinowaFont.text(14)).lineLimit(3) }
                Text(review.updatedAt, style: .date)
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                Label("編集する", systemImage: "square.and.pencil")
                    .font(MeshinowaFont.text(14, weight: .bold))
                    .foregroundStyle(MeshinowaTheme.green)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(18)
            .paperCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MyRestaurantMapView: View {
    var onFindRestaurants: () -> Void
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @State private var selected: SavedRestaurant?

    private var restaurants: [SavedRestaurant] {
        PersonalLibrary.restaurants(saved: saved.restaurants, reviews: reviews.reviews)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("自分が保存・評価したお店 \(restaurants.count)件")
                    .font(MeshinowaFont.text(18, weight: .black, relativeTo: .headline))
                if restaurants.isEmpty {
                    Button("マップでお店を探す", action: onFindRestaurants)
                        .buttonStyle(PaperButtonStyle())
                } else {
                    SavedRestaurantMap(restaurants: restaurants) { selected = $0 }
                        .frame(height: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .navigationTitle("マイマップ")
        .sheet(item: $selected) { RestaurantInformationView(item: $0.mapItem) }
    }
}
