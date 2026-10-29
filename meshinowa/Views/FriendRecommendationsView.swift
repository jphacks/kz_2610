import MapKit
import SwiftUI

/// サーバーから届いた友達の評価を表示するおすすめマップ。
struct FriendRecommendationsView: View {
    var dataset: FriendDataset
    var initialSelection: String? = nil
    var mapTitle = "友達のおすすめマップ"

    @State private var camera: GoogleMapPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        latitudinalMeters: 1100, longitudinalMeters: 1100
    ))
    @State private var selectedID: String?
    @State private var detail: FriendRestaurant?
    @State private var lens = FriendLens()
    @State private var showsLens = false
    @State private var highOnly = false
    @State private var genre: String?
    @Environment(\.dismiss) private var dismiss

    private var includedIDs: Set<String> {
        lens.includedFriendIDs(friends: dataset.friends, favorites: dataset.favoriteFriendIDs)
    }

    private func summary(for restaurant: FriendRestaurant) -> FriendRatingSummary {
        dataset.summary(for: restaurant, friendIDs: includedIDs)
    }

    private var visible: [FriendRestaurant] {
        dataset.restaurants.filter { restaurant in
            (genre == nil || restaurant.genre == genre)
                && (!highOnly || (summary(for: restaurant).average ?? 0) >= 4.5)
        }
    }

    private var rated: [FriendRestaurant] {
        visible.filter { summary(for: $0).count > 0 }
    }

    private var selected: FriendRestaurant? {
        visible.first { $0.id == selectedID }
    }

    var body: some View {
        GoogleMapCanvas(position: camera, pins: visible.map { restaurant in
            let summary = summary(for: restaurant)
            return GoogleMapPin(id: restaurant.id, title: restaurant.name, coordinate: restaurant.coordinate,
                                genre: restaurant.mapItem.foodGenre,
                                mark: summary.average.map { .friends($0) } ?? .none)
        }, selectedID: $selectedID)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { sheet }
        .reservesFloatingTabBarSpace()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // 実データはお店の場所が決まっていないので、全部が入るように地図を合わせる。
            if !dataset.restaurants.isEmpty { camera = .fit(dataset.restaurants.map(\.coordinate)) }
            if selectedID == nil { selectedID = initialSelection ?? rated.first?.id }
        }
        .onChange(of: visible.map(\.id)) { _, ids in
            if selectedID == nil || !ids.contains(selectedID!) { selectedID = rated.first?.id }
        }
        .onChange(of: dataset.restaurants.map(\.id)) { _, _ in
            if !dataset.restaurants.isEmpty { camera = .fit(dataset.restaurants.map(\.coordinate)) }
        }
        .sheet(item: $detail) { restaurant in
            RestaurantInformationView(item: restaurant.mapItem, friendIDs: includedIDs)
        }
        .sheet(isPresented: $showsLens) {
            FriendLensPicker(lens: $lens, dataset: dataset)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("戻る")
                VStack(alignment: .leading, spacing: 2) {
                    Text(mapTitle)
                        .font(MeshinowaFont.heading(18))
                    Text("友達\(dataset.friends.count)人の評価から")
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                Label("友達が行った店", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("友達が行ったお店")
                Rectangle().fill(MeshinowaTheme.outline).frame(width: 1, height: 26)
                Button { showsLens = true } label: {
                    HStack(spacing: 8) {
                        FriendAvatarStack(names: dataset.friends
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
                    ForEach(dataset.genres, id: \.self) { name in
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
        .background(MeshinowaTheme.ground.ignoresSafeArea(edges: .top))
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
                    FriendRestaurantCard(restaurant: selected, summary: summary(for: selected), dataset: dataset)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .id(selected.id)
                .transition(.opacity)
            } else {
                Text(rated.isEmpty
                     ? (!dataset.reviews.isEmpty
                        ? "この条件での評価はまだありません。友達や絞り込みを変えてみてください。"
                        : "友達の評価はまだありません。友達がお店を評価すると、ここに並びます。")
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
                .fill(MeshinowaTheme.ground)
                .shadow(color: .black.opacity(0.08), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeOut(duration: 0.2), value: selectedID)
    }
}

/// 地図の下に出る、写真を大きく見せるカード。
private struct FriendRestaurantCard: View {
    let restaurant: FriendRestaurant
    let summary: FriendRatingSummary
    let dataset: FriendDataset

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FoodGenreMark(genre: restaurant.mapItem.foodGenre, size: 64)
                .frame(maxWidth: .infinity)
                .background(MeshinowaTheme.photo)
                .frame(height: 130)
                .overlay(alignment: .bottomLeading) {
                    if let review = summary.reviews.first {
                        let name = dataset.friendName(review.friendID)
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
            Text("\(dataset.area(for: restaurant)) · \(restaurant.genre)")
                .lineLimit(1)
                .font(MeshinowaFont.text(15))
                .foregroundStyle(MeshinowaTheme.bodyText)
                .padding(.top, 2)
            if !summary.reviews.isEmpty {
                SoftTag(text: summary.reviews.map { dataset.friendName($0.friendID) }
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
