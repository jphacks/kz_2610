import MapKit
import SwiftUI

/// 地図の下に並ぶ店舗カード。店舗写真と自分の記録を表示する。
struct RestaurantPreview: View {
    let item: MKMapItem
    var loadsPhoto = true
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @EnvironmentObject private var friends: FriendStore
    @State private var showsDetails = false
    @State private var showsError = false
    @State private var showsRating = false

    var body: some View {
        let isLiked = saved.restaurant(for: item)?.isLiked == true
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Button { showsDetails = true } label: {
                    Text(item.name ?? "飲食店")
                        .font(MeshinowaFont.heading(18, relativeTo: .headline))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                reviewButton
                Rectangle()
                    .fill(MeshinowaTheme.hairline)
                    .frame(width: 1, height: 24)
                markButton(title: "いいね", symbol: "heart", isOn: isLiked,
                           tint: MeshinowaTheme.like) {
                    saved.setLiked(item, isLiked: !isLiked)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                RestaurantPhotoView(item: item, isActive: loadsPhoto, showsGoogleAttribution: false,
                                    imageHeight: 100)
                    .frame(width: 100)

                VStack(alignment: .leading, spacing: 8) {
                    detailLine(symbol: MapHomeView.symbol(for: item), text: item.restaurantCategory)
                    detailLine(symbol: "person.2", text: friends.ratingText(for: item))
                    detailLine(symbol: "mappin.and.ellipse",
                               text: item.placemark.title.map { $0.withoutPostalCode.replacingOccurrences(of: "\n", with: " ") }
                                   ?? "住所の情報がありません")
                }
                .contentShape(Rectangle())
                .onTapGesture { showsDetails = true }
            }
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(MeshinowaTheme.card)
            .shadow(color: .black.opacity(0.16), radius: 8, y: 2))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "お店の情報を開く") { showsDetails = true }
        .sheet(isPresented: $showsDetails) {
            RestaurantInformationView(item: item)
        }
        .sheet(isPresented: $showsRating) {
            QuickRatingSheet(item: item)
        }
        .alert("保存を変更できませんでした", isPresented: $showsError) {
            Button("閉じる", role: .cancel) {}
        } message: { Text(saved.errorMessage ?? "もう一度お試しください。") }
    }

    /// 行った＝レビュー。まだなら「☆ 評価」、レビュー済みなら自分の点数を出す。どちらも押すと星のシートが開く。
    private var reviewButton: some View {
        let rating = reviews.review(for: item)?.rating
        return Button { showsRating = true } label: {
            Group {
                if let rating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(rating, format: .number.precision(.fractionLength(1)))
                            .font(MeshinowaFont.number(18, relativeTo: .body))
                    }
                    .foregroundStyle(MeshinowaTheme.green)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: 14, weight: .semibold))
                        Text("評価")
                            .font(MeshinowaFont.text(14, weight: .bold))
                    }
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                }
            }
            .padding(.horizontal, 6)
            .frame(minWidth: 44, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reviews.loadError != nil)
        .accessibilityLabel(rating.map { "自分の評価、\($0.formatted(.number.precision(.fractionLength(1))))点。変更する" } ?? "行ったお店を評価する")
    }

    private func detailLine(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MeshinowaTheme.secondaryText)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(MeshinowaFont.text(13, relativeTo: .caption))
                .foregroundStyle(MeshinowaTheme.bodyText)
                .lineLimit(1)
        }
    }

    /// 名前の右に並ぶ、いいねの切り替え。オンのときは塗りつぶしの記号にする。
    private func markButton(title: String, symbol: String, isOn: Bool, tint: Color,
                            action: @escaping () -> Bool) -> some View {
        Button {
            showsError = !action()
        } label: {
            Image(systemName: isOn ? symbol + ".fill" : symbol)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(isOn ? tint : MeshinowaTheme.secondaryText)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "登録済み" : "未登録")
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
    enum Section: Hashable { case mine, info, friends }

    let item: MKMapItem
    @EnvironmentObject private var saved: SavedRestaurantStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var friends: FriendStore
    @State private var section: Section

    init(item: MKMapItem, initialSection: Section = .mine, friendIDs: Set<String>? = nil) {
        self.item = item
        self.friendIDs = friendIDs
        _section = State(initialValue: initialSection)
    }
    @State private var showsError = false

    let friendIDs: Set<String>?
    private var friendSummary: FriendRatingSummary { friends.summary(for: item, friendIDs: friendIDs) }

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
                }

                Text(item.name ?? "飲食店")
                    .font(MeshinowaFont.heading(28, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader)

                RestaurantPhotoView(item: item, expanded: true)

                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(symbol: "mappin.and.ellipse", text: item.placemark.title ?? "住所の情報がありません")
                    InfoRow(symbol: "fork.knife", text: item.restaurantCategory)
                    InfoRow(symbol: "person.2", text: friendSummary.average.map { "友達\(friendSummary.count)人の評価 " + $0.formatted(.number.precision(.fractionLength(1))) } ?? "この条件の友達の評価はまだありません")
                }

                RestaurantCollectionControls(item: item)

                UnderlineTabs(items: [
                    .init(value: Section.mine, title: "自分の記録"),
                    .init(value: Section.info, title: "情報"),
                    .init(value: Section.friends, title: "友達の声", badge: friendSummary.count > 0 ? "\(friendSummary.count)" : nil)
                ], selection: $section)

                switch section {
                case .mine:
                    MyReviewSection(item: item)
                case .info:
                    VStack(alignment: .leading, spacing: 14) {
                        InfoRow(symbol: "mappin.and.ellipse", text: item.placemark.title ?? "住所の情報がありません")
                        if let phone = item.phoneNumber, !phone.isEmpty {
                            InfoRow(symbol: "phone", text: phone) {
                                if let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                                    Link("電話", destination: url)
                                        .font(MeshinowaFont.text(14, weight: .bold))
                                }
                            }
                        }
                        InfoRow(symbol: "clock", text: "営業時間の情報がありません。来店前にお店へ確認してください。")
                    }
                case .friends:
                    FriendVoicesSection(summary: friendSummary)
                }
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .safeAreaInset(edge: .bottom) {
            DirectionsButton(item: item)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(MeshinowaTheme.paper)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("保存を変更できませんでした", isPresented: $showsError) {
            Button("閉じる", role: .cancel) {}
        } message: { Text(saved.errorMessage ?? "もう一度お試しください。") }
    }
}

struct DirectionsButton: View {
    let item: MKMapItem
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
        .buttonStyle(PaperButtonStyle())
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
