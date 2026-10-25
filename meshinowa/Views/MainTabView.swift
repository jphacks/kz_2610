import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable, CaseIterable { case map, saved, friends, profile }
    @State private var selection: Tab = .map

    var body: some View {
        ZStack {
            tab(.map) { MapHomeView(showsSavedShortcut: false) }
            tab(.saved) { SavedRestaurantsView(onFindRestaurants: { selection = .map }) }
            tab(.friends) { FriendsHomeView() }
            tab(.profile) { ProfileView(onFindRestaurants: { selection = .map }) }
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selection)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.floatingTabBarSpace, 80)
    }

    /// 切り替えても各タブの状態を残すため、すべて生かしたまま重ねる。
    private func tab<Content: View>(_ tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        let isActive = selection == tab
        return NavigationStack { content().reservesFloatingTabBarSpace() }
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
}

private struct FloatingTabBarSpaceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// 浮いたタブバーの高さ。タブの外では 0。
    var floatingTabBarSpace: CGFloat {
        get { self[FloatingTabBarSpaceKey.self] }
        set { self[FloatingTabBarSpaceKey.self] = newValue }
    }
}

private struct ReservesFloatingTabBarSpace: ViewModifier {
    @Environment(\.floatingTabBarSpace) private var space

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: space).allowsHitTesting(false)
        }
    }
}

extension View {
    /// NavigationStack の中では外側の safeAreaInset が届かないため、画面ごとにタブバーの分をあける。
    func reservesFloatingTabBarSpace() -> some View {
        modifier(ReservesFloatingTabBarSpace())
    }
}

private struct FloatingTabBar: View {
    @Binding var selection: MainTabView.Tab

    var body: some View {
        HStack(spacing: 0) {
            item(.map, title: "マップ", symbol: "map")
            item(.saved, title: "保存", symbol: "heart")
            item(.friends, title: "友達", symbol: "person.2")
            item(.profile, title: "プロフィール", symbol: "person.crop.circle")
        }
        .padding(.horizontal, 6)
        .frame(height: 68)
        .background(Capsule().fill(MeshinowaTheme.card).shadow(color: .black.opacity(0.14), radius: 10, y: 2))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func item(_ tab: MainTabView.Tab, title: String, symbol: String) -> some View {
        let isActive = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Group {
                    if tab == .map && isActive {
                        BowlMark(size: 24)
                    } else {
                        Image(systemName: isActive ? symbol + ".fill" : symbol)
                            .font(.system(size: 19, weight: isActive ? .semibold : .regular))
                    }
                }
                .frame(width: 44, height: 30)
                .background(Capsule().fill(isActive ? MeshinowaTheme.mint : .clear))
                Text(title)
                    .font(isActive ? MeshinowaFont.text(11, weight: .bold, relativeTo: .caption2)
                                   : MeshinowaFont.text(11, relativeTo: .caption2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? MeshinowaTheme.green : MeshinowaTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .animation(.snappy(duration: 0.2), value: isActive)
    }
}

struct FriendsHomeView: View {
    private enum Section: Hashable { case recommended, feed }
    @State private var section: Section = .recommended

    private var recentReviews: [DemoReview] {
        DemoRecommendations.reviews
            .filter { review in !DemoRecommendations.reviews.contains { $0.friendID == review.friendID && $0.restaurantID == review.restaurantID && $0.updatedAt > review.updatedAt } }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: "友達")
                    .padding(.horizontal, 20)
                UnderlineTabs(items: [
                    .init(value: Section.recommended, title: "おすすめ"),
                    .init(value: Section.feed, title: "フィード")
                ], selection: $section)
                .padding(.horizontal, 20)

                if section == .recommended {
                    recommended
                } else {
                    feed
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var recommended: some View {
        VStack(alignment: .leading, spacing: 24) {
            NavigationLink {
                DemoRecommendationsView()
            } label: {
                banner
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("友達の最近の記録")
                        .font(MeshinowaFont.heading(20))
                    SoftTag(text: "架空", tone: .neutral, compact: true)
                }
                .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentReviews.prefix(6)) { review in
                            NavigationLink { DemoRecommendationsView(initialSelection: review.restaurantID) } label: {
                                RecentReviewCard(review: review)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Text("友達との接続（ログインと申請・承認）は準備中です。現在のレビューはこの端末だけの記録で、ここに出る友達・店舗・レビューはすべて架空です。")
                .font(MeshinowaFont.text(12, relativeTo: .caption))
                .foregroundStyle(MeshinowaTheme.secondaryText)
                .padding(.horizontal, 20)
        }
        .padding(.top, 18)
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("meshinowa")
                    .font(MeshinowaFont.heading(14))
                    .foregroundStyle(MeshinowaTheme.green)
                Text("友達の「うまい」を\n地図に集めよう")
                    .font(MeshinowaFont.heading(21, relativeTo: .title2))
                    .fixedSize(horizontal: false, vertical: true)
                Text("友達との接続は準備中です。")
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.bodyText)
                HStack(spacing: 4) {
                    Text("架空データで試す")
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .font(MeshinowaFont.text(14, weight: .bold))
                .foregroundStyle(MeshinowaTheme.green)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            BowlMark(size: 150)
                .opacity(0.9)
                .offset(x: 34, y: 30)
        }
        .background(MeshinowaTheme.mint)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("架空のデータで友達の評価マップを開きます")
    }

    private var feed: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("架空の友達の記録")
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                Spacer()
            }
            .padding(.vertical, 12)
            ForEach(recentReviews) { review in
                let restaurant = DemoRecommendations.restaurants.first { $0.id == review.restaurantID }
                let name = DemoRecommendations.friendName(review.friendID)
                HStack(alignment: .top, spacing: 12) {
                    FriendAvatar(name: name, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(name)が評価")
                                .font(MeshinowaFont.text(14, weight: .bold))
                            Spacer()
                            Text(review.rating, format: .number.precision(.fractionLength(1)))
                                .font(MeshinowaFont.number(17, relativeTo: .body))
                                .foregroundStyle(MeshinowaTheme.green)
                        }
                        Text(restaurant?.name ?? "")
                            .font(MeshinowaFont.heading(16))
                        Text("「\(review.comment)」")
                            .font(MeshinowaFont.text(14))
                            .foregroundStyle(MeshinowaTheme.bodyText)
                    }
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct RecentReviewCard: View {
    let review: DemoReview

    var body: some View {
        let restaurant = DemoRecommendations.restaurants.first { $0.id == review.restaurantID }
        let name = DemoRecommendations.friendName(review.friendID)
        VStack(alignment: .leading, spacing: 8) {
            PhotoPlaceholder(symbol: restaurant.map { DemoRecommendations.symbol(for: $0) } ?? "fork.knife",
                             tint: restaurant.map { DemoRecommendations.photoTint(for: $0) } ?? MeshinowaTheme.photo)
                .frame(width: 200, height: 120)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        FriendAvatar(name: name, size: 22)
                        Text(name).font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
                    }
                    .padding(.vertical, 4)
                    .padding(.leading, 4)
                    .padding(.trailing, 10)
                    .background(.white, in: Capsule())
                    .padding(8)
                }
            HStack(alignment: .firstTextBaseline) {
                Text(restaurant?.name ?? "")
                    .font(MeshinowaFont.heading(15))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(review.rating, format: .number.precision(.fractionLength(1)))
                    .font(MeshinowaFont.number(15, relativeTo: .body))
                    .foregroundStyle(MeshinowaTheme.green)
                    .fixedSize()
            }
            Text(review.comment)
                .font(MeshinowaFont.text(13, relativeTo: .caption))
                .foregroundStyle(MeshinowaTheme.bodyText)
                .lineLimit(2)
                .frame(height: 36, alignment: .top)
        }
        .frame(width: 200)
        .accessibilityElement(children: .combine)
    }
}
