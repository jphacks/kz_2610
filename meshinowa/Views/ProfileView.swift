import SwiftUI

struct ProfileView: View {
    var onFindRestaurants: () -> Void
    @EnvironmentObject private var reviews: LocalReviewStore
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var friends: FriendStore
    @State private var editing: LocalReview?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(MeshinowaTheme.green)
                        .frame(width: 64, height: 64)
                        .background(MeshinowaTheme.mint, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        ScreenTitle(text: "あなたの記録")
                        Text("この端末のプロフィール")
                            .font(MeshinowaFont.text(13, relativeTo: .caption))
                            .foregroundStyle(MeshinowaTheme.secondaryText)
                    }
                }

                HStack(spacing: 0) {
                    statistic("行った（レビュー）", count: reviews.reviews.count)
                    divider
                    statistic("いいね", count: saved.restaurants.filter(\.isLiked).count)
                }
                .padding(.vertical, 16)
                .paperCard()

                VStack(spacing: 0) {
                    NavigationLink {
                        MyReviewsView(onFindRestaurants: onFindRestaurants)
                    } label: { linkRow("自分のレビュー一覧", symbol: "text.bubble") }
                    NavigationLink {
                        MyRestaurantMapView(onFindRestaurants: onFindRestaurants)
                    } label: { linkRow("マイマップ", symbol: "map") }
                }
                .buttonStyle(.plain)

                if let error = reviews.loadError {
                    Text(error).font(MeshinowaFont.text(14))
                    Button("レビューを再読み込み") { reviews.reload() }
                        .buttonStyle(PaperButtonStyle(kind: .secondary))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近のレビュー")
                        .font(MeshinowaFont.heading(20, relativeTo: .title2))
                    if reviews.reviews.isEmpty && reviews.loadError == nil {
                        Text("まだレビューがありません。お店の詳細から星だけでも記録できます。")
                            .font(MeshinowaFont.text(14))
                            .foregroundStyle(MeshinowaTheme.bodyText)
                            .padding(.top, 6)
                    }
                    ForEach(Array(reviews.reviews.prefix(3))) { review in
                        LocalReviewRow(review: review) { editing = review }
                    }
                }
                Text(friends.isAvailable
                     ? "ゲストとして利用中です。評価・ひとこと・おすすめ料理は友達に共有され、写真と来店日はこの端末だけに保存します。"
                     : "サーバーに接続していないため、記録はこの端末だけに保存されます。アプリを削除すると端末内のデータも消えます。")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { ReviewEditor(item: $0.restaurant.mapItem, existing: $0) }
    }

    private var divider: some View {
        Rectangle().fill(MeshinowaTheme.hairline).frame(width: 1, height: 40)
    }

    private func statistic(_ title: String, count: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(MeshinowaFont.number(26))
            Text(title)
                .font(MeshinowaFont.text(13, relativeTo: .caption))
                .foregroundStyle(MeshinowaTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)、\(count)件")
    }

    private func linkRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title).font(MeshinowaFont.text(16))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MeshinowaTheme.outline)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
        .contentShape(Rectangle())
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
        .reservesFloatingTabBarSpace()
        .sheet(item: $editing) { ReviewEditor(item: $0.restaurant.mapItem, existing: $0) }
    }
}

private struct LocalReviewRow: View {
    let review: LocalReview
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(review.restaurant.name)
                        .font(MeshinowaFont.heading(17))
                    Spacer(minLength: 8)
                    SoftTag(text: "自分 " + review.rating.formatted(.number.precision(.fractionLength(1))), tone: .mustard)
                }
                if !review.comment.isEmpty {
                    Text(review.comment)
                        .font(MeshinowaFont.text(14))
                        .foregroundStyle(MeshinowaTheme.bodyText)
                        .lineLimit(3)
                }
                HStack {
                    Text(review.updatedAt, style: .date)
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                    Spacer()
                    Label("編集する", systemImage: "square.and.pencil")
                        .font(MeshinowaFont.text(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.green)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
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
                    SavedRestaurantMap(restaurants: restaurants,
                                       ratings: Dictionary(uniqueKeysWithValues: reviews.reviews.map { ($0.id, $0.rating) })) {
                        selected = $0
                    }
                        .frame(height: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .navigationTitle("マイマップ")
        .reservesFloatingTabBarSpace()
        .sheet(item: $selected) { RestaurantInformationView(item: $0.mapItem) }
    }
}
