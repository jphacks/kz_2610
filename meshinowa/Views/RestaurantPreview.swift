import MapKit
import SwiftUI

/// 地図の下に並ぶ店舗カード。店舗写真と自分の記録を表示する。
struct RestaurantPreview: View {
    let item: MKMapItem
    var loadsPhoto = true
    var position = 1
    var total = 0
    var onShowList: (() -> Void)? = nil
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @EnvironmentObject private var friends: FriendStore
    @State private var showsDetails = false
    @State private var showsError = false
    @State private var showsRating = false

    var body: some View {
        let isLiked = saved.restaurant(for: item)?.isLiked == true
        let rating = reviews.review(for: item)?.rating
        VStack(alignment: .leading, spacing: 10) {
            RestaurantPhotoView(item: item, isActive: loadsPhoto, showsGoogleAttribution: false,
                                imageHeight: 128, overlaysCredits: true)
                .overlay(alignment: .topLeading) { GenreRibbon(genre: item.foodGenre).padding(.leading, 12) }
                .overlay(alignment: .topTrailing) {
                    if let onShowList, total > 0 {
                        Button(action: onShowList) {
                            Text("\(position) / \(total)")
                                .font(MeshinowaFont.number(12, relativeTo: .caption))
                                .foregroundStyle(MeshinowaTheme.paper)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(MeshinowaTheme.ink.opacity(0.55), in: Capsule())
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        .accessibilityLabel("検索結果\(total)件を一覧で見る、\(position)件目")
                    }
                }
            Button { showsDetails = true } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name ?? "飲食店")
                        .font(MeshinowaFont.wa(21, relativeTo: .title3))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let average = friends.summary(for: item).average {
                        Label("友達 \(average.formatted(.number.precision(.fractionLength(1))))", systemImage: "person.2")
                            .font(MeshinowaFont.text(13, weight: .bold))
                            .foregroundStyle(MeshinowaTheme.green)
                    }
                    Label(item.placemark.title?.withoutPostalCode.replacingOccurrences(of: "\n", with: " ")
                          ?? "住所の情報がありません", systemImage: "mappin.and.ellipse")
                        .font(MeshinowaFont.text(13, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.bodyText)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("お店の詳細を開きます")
            HStack(spacing: 8) {
                Button { showsRating = true } label: {
                    RestaurantActionTile(title: rating.map { "自分 " + $0.formatted(.number.precision(.fractionLength(1))) } ?? "評価する",
                                         symbol: rating == nil ? "star" : "star.fill",
                                         tint: rating == nil ? MeshinowaTheme.accent : MeshinowaTheme.mustardInk,
                                         background: rating == nil ? MeshinowaTheme.field : MeshinowaTheme.mustardSoft)
                }
                .disabled(reviews.loadError != nil)
                .accessibilityLabel(rating.map { "自分の評価、\($0.formatted(.number.precision(.fractionLength(1))))点。変更する" } ?? "行ったお店を評価する")
                Button { showsError = !saved.setLiked(item, isLiked: !isLiked) } label: {
                    RestaurantActionTile(title: "いいね", symbol: isLiked ? "heart.fill" : "heart",
                                         tint: MeshinowaTheme.like,
                                         background: isLiked ? MeshinowaTheme.likeSoft : MeshinowaTheme.field)
                }
                .accessibilityLabel("いいね")
                .accessibilityValue(isLiked ? "登録済み" : "未登録")
                SwipeDiscoveryEntry.wantToGoButton(item: item, tile: true)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .padding(10)
        .background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "お店の情報を開く") { showsDetails = true }
        .sheet(isPresented: $showsDetails) { RestaurantInformationView(item: item) }
        .sheet(isPresented: $showsRating) { QuickRatingSheet(item: item) }
        .alert("保存を変更できませんでした", isPresented: $showsError) {
            Button("閉じる", role: .cancel) {}
        } message: { Text(saved.errorMessage ?? "もう一度お試しください。") }
    }
}

/// 星だけで「行った」を記録する小さなシート。ひとことや写真は詳しいレビュー画面で足せる。
struct QuickRatingSheet: View {
    let item: MKMapItem
    @EnvironmentObject private var reviews: LocalReviewStore
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Double = 0
    @State private var showsEditor = false
    @State private var showsSeal = false
    @State private var error: String?

    var body: some View {
        let existing = reviews.review(for: item)
        VStack(alignment: .leading, spacing: 14) {
            ReviewShopHeader(item: item)
            VStack(spacing: 4) {
                Text(existing == nil ? "行った？どうだった？" : "評価を変える")
                    .font(MeshinowaFont.heading(16))
                    .foregroundStyle(MeshinowaTheme.bodyText)
                BigStarRating(rating: $rating)
            }
            HStack(spacing: 10) {
                Button("ひとことも書く") { showsEditor = true }
                    .buttonStyle(PaperButtonStyle(kind: .secondary))
                Button(existing == nil ? "記録する" : "更新する") { save(existing: existing) }
                    .buttonStyle(PaperButtonStyle())
                    .disabled(rating < 1 || showsSeal)
            }
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .padding(20)
        .ratingSealOnSave(rating: rating, isPresented: $showsSeal) { dismiss() }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .presentationBackground(MeshinowaTheme.paper)
        .onAppear { rating = existing?.rating ?? 0 }
        .sheet(isPresented: $showsEditor, onDismiss: {
            if reviews.review(for: item) != nil { dismiss() }
        }) {
            ReviewEditor(item: item, existing: existing, initialRating: rating)
        }
        .alert("記録できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("閉じる", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func save(existing: LocalReview?) {
        do {
            // 星だけを変え、ひとことや写真など書いてあるものはそのまま残す。
            try reviews.save(item: item, rating: rating, comment: existing?.comment ?? "",
                             dish: existing?.dish ?? "", wantAgain: existing?.wantAgain ?? false,
                             visitedOn: existing?.visitedOn)
            showsSeal = true
        } catch { self.error = error.localizedDescription }
    }
}

struct RestaurantInformationView: View {
    let item: MKMapItem
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var friends: FriendStore
    @State private var lens: FriendLens
    @State private var showsLens = false
    @State private var showsError = false

    init(item: MKMapItem, friendIDs: Set<String>? = nil) {
        self.item = item
        _lens = State(initialValue: friendIDs.map {
            FriendLens(mode: .selectedFriends, selectedFriendIDs: $0)
        } ?? FriendLens())
    }

    private var friendSummary: FriendRatingSummary {
        let dataset = friends.dataset
        let ids = lens.includedFriendIDs(friends: dataset.friends, favorites: dataset.favoriteFriendIDs)
        return friends.summary(for: item, friendIDs: ids)
    }

    var body: some View {
        let isLiked = saved.restaurant(for: item)?.isLiked == true
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(CircleIconButtonStyle())
                        .accessibilityLabel("閉じる")
                    Spacer()
                    ShareLink(item: [item.name, item.placemark.title].compactMap { $0 }.joined(separator: "\n")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("店名と住所を共有")
                    Button {
                        showsError = !saved.setLiked(item, isLiked: !isLiked)
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? MeshinowaTheme.like : MeshinowaTheme.ink)
                    }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("いいね")
                    .accessibilityValue(isLiked ? "登録済み" : "未登録")
                    SwipeDiscoveryEntry.wantToGoButton(item: item, compact: true)
                }

                Text(item.name ?? "飲食店")
                    .font(MeshinowaFont.heading(28, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader)

                RestaurantPhotoView(item: item, expanded: true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("友達の評価").font(MeshinowaFont.text(16, weight: .bold))
                        Spacer()
                        Button { showsLens = true } label: {
                            HStack(spacing: 6) {
                                Text(lens.mode.title)
                                Image(systemName: "chevron.down")
                            }
                        }
                        .buttonStyle(PillButtonStyle(isOn: false))
                        .accessibilityLabel("誰の評価で見るか選ぶ")
                    }
                    if let average = friendSummary.average {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(average, format: .number.precision(.fractionLength(1)))
                                .font(MeshinowaFont.number(46, relativeTo: .largeTitle))
                                .foregroundStyle(MeshinowaTheme.green)
                            Text("友達\(friendSummary.count)人の平均")
                                .font(MeshinowaFont.text(14))
                                .foregroundStyle(MeshinowaTheme.bodyText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    FriendVoicesSection(summary: friendSummary)
                }

                if reviews.review(for: item) != nil || reviews.loadError != nil {
                    MyReviewSection(item: item)
                }

                VStack(alignment: .leading, spacing: 14) {
                    InfoRow(symbol: "mappin.and.ellipse", text: item.placemark.title ?? "住所の情報がありません")
                    InfoRow(symbol: "fork.knife", text: item.restaurantCategory)
                    if let phone = item.phoneNumber, !phone.isEmpty {
                        InfoRow(symbol: "phone", text: phone) {
                            if let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                                Link("電話", destination: url)
                                    .font(MeshinowaFont.text(14, weight: .bold))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                DirectionsButton(item: item, kind: .secondary)
                RestaurantCollectionControls(item: item)
            }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(MeshinowaTheme.paper)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showsLens) { FriendLensPicker(lens: $lens, dataset: friends.dataset) }
        .alert("保存を変更できませんでした", isPresented: $showsError) {
            Button("閉じる", role: .cancel) {}
        } message: { Text(saved.errorMessage ?? "もう一度お試しください。") }
    }
}

struct DirectionsButton: View {
    let item: MKMapItem
    var kind: PaperButtonStyle.Kind = .primary
    @State private var showsError = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            let coordinate = item.placemark.coordinate
            var components = URLComponents(string: "https://www.google.com/maps/dir/")!
            components.queryItems = [URLQueryItem(name: "api", value: "1"),
                                     URLQueryItem(name: "destination", value: "\(coordinate.latitude),\(coordinate.longitude)"),
                                     URLQueryItem(name: "travelmode", value: "walking")]
            if let id = item.googleDetails?.placeID {
                components.queryItems?.append(URLQueryItem(name: "destination_place_id", value: id))
            }
            if let url = components.url {
                openURL(url) { accepted in showsError = !accepted }
            } else { showsError = true }
        } label: {
            Label("経路", systemImage: "figure.walk")
        }
        .buttonStyle(PaperButtonStyle(kind: kind))
        .accessibilityLabel("経路を見る")
        .accessibilityHint("Google Mapsで徒歩の経路を開きます")
        .alert("Google Mapsを開けませんでした", isPresented: $showsError) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("時間をおいて、もう一度お試しください。")
        }
    }
}

extension String {
    /// 先頭の「〒100-0005」を省いた住所。一覧やカードで場所が先に読めるようにする。
    var withoutPostalCode: String {
        replacingOccurrences(of: #"^〒\d{3}-?\d{4}[\s,、]*"#, with: "", options: .regularExpression)
    }

    /// 丁目を含む場合だけ、町名以降を切り出す。判断できない住所は省略しない。
    var restaurantLocalAddress: String {
        let address = withoutPostalCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[\s,、]+日本$"#, with: "", options: .regularExpression)
        guard let range = address.range(of: #"(?<=[市区郡])[^市区郡、,]+?[0-9０-９一二三四五六七八九十]+丁目"#, options: .regularExpression) else { return address }
        return String(address[range.lowerBound...])
    }

    var restaurantArea: String {
        let address = restaurantLocalAddress
        guard let range = address.range(of: #"^.+?丁目"#, options: .regularExpression) else { return address }
        return String(address[range])
    }

}

extension MKMapItem {
    var restaurantCategory: String {
        switch pointOfInterestCategory {
        case .cafe: return "カフェ"
        case .bakery: return "ベーカリー"
        case .brewery: return "ブルワリー"
        default: return "飲食店"
        }
    }
}

/// お店の詳細の「友達の声」。友達の最新の評価とひとことを新しい順に並べる。
private struct FriendVoicesSection: View {
    let summary: FriendRatingSummary
    @EnvironmentObject private var friends: FriendStore

    var body: some View {
        if summary.reviews.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("友達の声はまだありません")
                    .font(MeshinowaFont.heading(17))
                Text(friends.isAvailable
                     ? "友達がこのお店を評価すると、ここに評価とひとことが並びます。"
                     : "サーバーに接続すると、友達の評価とひとことが並びます。")
                    .font(MeshinowaFont.text(14))
                    .foregroundStyle(MeshinowaTheme.bodyText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MeshinowaTheme.mint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            let dataset = friends.dataset
            VStack(alignment: .leading, spacing: 0) {
                ForEach(summary.reviews) { review in
                    let name = dataset.friendName(review.friendID)
                    HStack(alignment: .top, spacing: 12) {
                        FriendAvatar(name: name, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(name).font(MeshinowaFont.text(14, weight: .bold))
                                Spacer()
                                Text(review.rating, format: .number.precision(.fractionLength(1)))
                                    .font(MeshinowaFont.number(16, relativeTo: .body))
                                    .foregroundStyle(MeshinowaTheme.green)
                            }
                            ReviewUpdatedDate(date: review.updatedAt)
                            if !review.comment.isEmpty {
                                Text(review.comment)
                                    .font(MeshinowaFont.text(15))
                                    .foregroundStyle(MeshinowaTheme.bodyText)
                            }
                            if !review.dish.isEmpty {
                                Label(review.dish, systemImage: "fork.knife")
                                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                                    .foregroundStyle(MeshinowaTheme.secondaryText)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

extension FriendStore {
    /// プレビュー・詳細の1行。友達がいなくても0点は付けない。
    func ratingText(for item: MKMapItem) -> String {
        guard isAvailable else { return "友達の評価はサーバー接続後に表示" }
        let summary = summary(for: item)
        guard let average = summary.average else { return "友達の評価はまだありません" }
        return "友達\(summary.count)人の評価 " + average.formatted(.number.precision(.fractionLength(1)))
    }
}

/// 来店日ではなく、サーバーで評価が最後に更新された日付。
struct ReviewUpdatedDate: View {
    let date: Date

    var body: some View {
        if date != .distantPast {
            HStack(spacing: 4) {
                Text("評価更新")
                Text(date, format: .dateTime.year().month().day())
            }
            .font(MeshinowaFont.text(12, relativeTo: .caption))
            .foregroundStyle(MeshinowaTheme.secondaryText)
            .accessibilityElement(children: .combine)
        }
    }
}
