import MapKit
import SwiftUI

struct DemoRecommendationsView: View {
    var initialSelection: String? = nil

    @State private var camera: GoogleMapPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        latitudinalMeters: 1100, longitudinalMeters: 1100
    ))
    @State private var selectedID: String?
    @State private var detail: DemoRestaurant?
    @State private var lens = FriendLens()
    @State private var showsLens = false
    @State private var highOnly = false
    @State private var genre: String?
    @Environment(\.dismiss) private var dismiss

    private var includedIDs: Set<String> {
        lens.includedFriendIDs(friends: DemoRecommendations.friends,
                               favorites: DemoRecommendations.favoriteFriendIDs)
    }

    private func summary(for restaurant: DemoRestaurant) -> FriendRatingSummary {
        DemoRecommendations.summary(for: restaurant, friendIDs: includedIDs)
    }

    private var visible: [DemoRestaurant] {
        DemoRecommendations.restaurants.filter { restaurant in
            (genre == nil || restaurant.genre == genre)
                && (!highOnly || (summary(for: restaurant).average ?? 0) >= 4.5)
        }
    }

    private var rated: [DemoRestaurant] {
        visible.filter { summary(for: $0).count > 0 }
    }

    private var selected: DemoRestaurant? {
        visible.first { $0.id == selectedID }
    }

    var body: some View {
        GoogleMapCanvas(position: camera, pins: visible.map { restaurant in
            let summary = summary(for: restaurant)
            return GoogleMapPin(id: restaurant.id, title: restaurant.name, coordinate: restaurant.coordinate,
                                scoreTag: summary.count > 0 ? "友達\(summary.count)" : "未評価",
                                scoreTitle: summary.average.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
        }, selectedID: $selectedID)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { sheet }
        .reservesFloatingTabBarSpace()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if selectedID == nil { selectedID = initialSelection ?? "diner" }
        }
        .onChange(of: visible.map(\.id)) { _, ids in
            if let id = selectedID, !ids.contains(id) { selectedID = rated.first?.id }
        }
        .sheet(item: $detail) { restaurant in
            DemoRestaurantDetail(restaurant: restaurant, summary: summary(for: restaurant), lensTitle: lens.mode.title)
        }
        .sheet(isPresented: $showsLens) {
            FriendLensPicker(lens: $lens)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("戻る")
                VStack(alignment: .leading, spacing: 2) {
                    Text("友達のおすすめマップ")
                        .font(MeshinowaFont.heading(18))
                    Text("DEMO · 店舗・友達・レビューはすべて架空です")
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                Label("東京駅周辺", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("エリア、東京駅周辺")
                Rectangle().fill(MeshinowaTheme.outline).frame(width: 1, height: 26)
                Button { showsLens = true } label: {
                    HStack(spacing: 8) {
                        FriendAvatarStack(names: DemoRecommendations.friends
                            .filter { includedIDs.contains($0.id) }.map(\.name), size: 20)
                        Text(lensShortTitle)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Friend Lens、\(lens.mode.title)、\(includedIDs.count)人")
                .accessibilityHint("誰の評価で表示するかを変更します")
            }
            .font(MeshinowaFont.text(15))
            .frame(height: 44)
            .overlay(Capsule().strokeBorder(MeshinowaTheme.ink, lineWidth: 1.5))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterCount
                    Button("友達4.5以上") { highOnly.toggle() }
                        .buttonStyle(PillButtonStyle(isOn: highOnly))
                        .accessibilityAddTraits(highOnly ? .isSelected : [])
                    ForEach(["洋食", "カフェ", "ラーメン", "ベーカリー"], id: \.self) { name in
                        Button(name) { genre = genre == name ? nil : name }
                            .buttonStyle(PillButtonStyle(isOn: genre == name))
                            .accessibilityAddTraits(genre == name ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(MeshinowaTheme.paper.ignoresSafeArea(edges: .top))
    }

    private var lensShortTitle: String {
        switch lens.mode {
        case .allFriends: return "友達 全員"
        case .favoriteFriends: return "お気に入り"
        case .selectedFriends: return "\(includedIDs.count)人を選択"
        }
    }

    private var filterCount: some View {
        let count = (highOnly ? 1 : 0) + (genre == nil ? 0 : 1)
        return Button {
            highOnly = false
            genre = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                if count > 0 {
                    Text("\(count)")
                        .font(MeshinowaFont.number(12, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.ink)
                        .frame(width: 20, height: 20)
                        .background(.white, in: Circle())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(MeshinowaTheme.ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "絞り込み\(count)件、タップで解除" : "絞り込みなし")
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(MeshinowaTheme.outline).frame(width: 40, height: 5)
                .padding(.top, 8)
            Text("友達のおすすめ \(rated.count)軒")
                .font(MeshinowaFont.heading(17))
                .padding(.top, 10)
            Label("点数は友達の評価だけで出しています", systemImage: "info.circle")
                .font(MeshinowaFont.text(13, relativeTo: .caption))
                .foregroundStyle(MeshinowaTheme.bodyText)
                .padding(.top, 2)

            if let selected {
                Button { detail = selected } label: {
                    DemoRestaurantCard(restaurant: selected, summary: summary(for: selected))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .id(selected.id)
                .transition(.opacity)
            } else {
                Text(rated.isEmpty
                     ? "この条件での評価はまだありません。友達や絞り込みを変えてみてください。"
                     : "ピンをタップすると、友達のおすすめが見られます。")
                    .font(MeshinowaFont.text(14))
                    .foregroundStyle(MeshinowaTheme.bodyText)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 24)
            }
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                .fill(MeshinowaTheme.card)
                .shadow(color: .black.opacity(0.08), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeOut(duration: 0.2), value: selectedID)
    }
}

/// 地図の下に出る、写真を大きく見せるカード。
private struct DemoRestaurantCard: View {
    let restaurant: DemoRestaurant
    let summary: FriendRatingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoPlaceholder(symbol: DemoRecommendations.symbol(for: restaurant),
                             tint: DemoRecommendations.photoTint(for: restaurant))
                .frame(height: 130)
                .overlay(alignment: .bottomLeading) {
                    if let review = summary.reviews.first {
                        let name = DemoRecommendations.friendName(review.friendID)
                        HStack(spacing: 8) {
                            FriendAvatar(name: name, size: 26)
                            Text(review.comment)
                                .font(MeshinowaFont.text(13, relativeTo: .caption))
                                .lineLimit(1)
                        }
                        .padding(.vertical, 6)
                        .padding(.leading, 6)
                        .padding(.trailing, 12)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .padding(10)
                        .padding(.trailing, 50)
                    }
                }

            HStack(alignment: .top) {
                Text(restaurant.name)
                    .font(MeshinowaFont.heading(21, relativeTo: .title2))
                Spacer(minLength: 8)
                RatingStamp(rating: summary.average, friendCount: summary.count, size: 20)
            }
            .padding(.top, 12)
            Text("\(DemoRecommendations.area(for: restaurant)) · \(restaurant.genre)")
                .font(MeshinowaFont.text(15))
                .foregroundStyle(MeshinowaTheme.bodyText)
                .padding(.top, 2)
            if !summary.reviews.isEmpty {
                SoftTag(text: summary.reviews.map { DemoRecommendations.friendName($0.friendID) }
                    .joined(separator: "・") + "が行った")
                    .padding(.top, 10)
            }
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("お店の詳細を開きます")
    }
}

struct DemoNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text("DEMO · 店舗・友達・レビューはすべて架空です。実際の店舗情報や保存一覧には反映されません。")
                .font(MeshinowaFont.text(13, relativeTo: .caption))
        }
        .foregroundStyle(MeshinowaTheme.bodyText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MeshinowaTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct DemoRestaurantDetail: View {
    private enum Section: Hashable { case voices, info }

    let restaurant: DemoRestaurant
    let summary: FriendRatingSummary
    let lensTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .voices

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(CircleIconButtonStyle())
                        .accessibilityLabel("閉じる")
                    Spacer()
                }
                Text(restaurant.name)
                    .font(MeshinowaFont.heading(28, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(symbol: "mappin.and.ellipse", text: DemoRecommendations.area(for: restaurant))
                    InfoRow(symbol: "fork.knife", text: restaurant.genre)
                    HStack(spacing: 12) {
                        FriendAvatarStack(names: summary.reviews.map { DemoRecommendations.friendName($0.friendID) })
                        if let average = summary.average {
                            Text(average, format: .number.precision(.fractionLength(1)))
                                .font(MeshinowaFont.number(18, relativeTo: .body))
                                .foregroundStyle(MeshinowaTheme.green)
                            Text("友達\(summary.count)人の評価（\(lensTitle)）")
                                .font(MeshinowaFont.text(14))
                                .foregroundStyle(MeshinowaTheme.bodyText)
                        } else {
                            Text("このLensでの評価はまだありません")
                                .font(MeshinowaFont.text(14))
                                .foregroundStyle(MeshinowaTheme.bodyText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                HStack(spacing: 6) {
                    PhotoPlaceholder(symbol: DemoRecommendations.symbol(for: restaurant),
                                     tint: DemoRecommendations.photoTint(for: restaurant), cornerRadius: 12)
                    VStack(spacing: 6) {
                        PhotoPlaceholder(symbol: "cup.and.saucer", tint: MeshinowaTheme.field, cornerRadius: 12)
                        PhotoPlaceholder(symbol: "photo", tint: MeshinowaTheme.field, cornerRadius: 12)
                    }
                    .frame(width: 110)
                }
                .frame(height: 180)

                UnderlineTabs(items: [
                    .init(value: Section.voices, title: "友達の声", badge: "\(summary.count)"),
                    .init(value: Section.info, title: "情報")
                ], selection: $section)

                if section == .voices {
                    if summary.reviews.isEmpty {
                        Text("このLensでの評価はまだありません。")
                            .font(MeshinowaFont.text(14))
                            .foregroundStyle(MeshinowaTheme.bodyText)
                    }
                    ForEach(summary.reviews) { review in
                        DemoReviewRow(review: review)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        InfoRow(symbol: "clock", text: "営業時間は架空のため表示していません")
                        DemoNotice()
                    }
                }
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .presentationDragIndicator(.visible)
    }
}

private struct DemoReviewRow: View {
    let review: DemoReview

    var body: some View {
        let name = DemoRecommendations.friendName(review.friendID)
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
                Text(review.comment)
                    .font(MeshinowaFont.text(15))
                    .foregroundStyle(MeshinowaTheme.bodyText)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

extension DemoRecommendations {
    static func symbol(for restaurant: DemoRestaurant) -> String {
        switch restaurant.genre {
        case "カフェ": return "cup.and.saucer"
        case "ラーメン": return "takeoutbag.and.cup.and.straw"
        case "ベーカリー": return "birthday.cake"
        default: return "fork.knife"
        }
    }

    static func photoTint(for restaurant: DemoRestaurant) -> Color {
        switch restaurant.genre {
        case "カフェ": return Color(red: 0.90, green: 0.86, blue: 0.82)
        case "ラーメン": return Color(red: 0.94, green: 0.89, blue: 0.78)
        case "ベーカリー": return Color(red: 0.94, green: 0.89, blue: 0.80)
        default: return MeshinowaTheme.photo
        }
    }

    static func area(for restaurant: DemoRestaurant) -> String {
        restaurant.coordinate.longitude < 139.7671 ? "千代田区丸の内（架空）" : "中央区八重洲（架空）"
    }
}
