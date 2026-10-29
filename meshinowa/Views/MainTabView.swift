import MapKit
import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable, CaseIterable { case map, saved, friends, profile }
    @EnvironmentObject private var friends: FriendStore
    @State private var selection: Tab = .map
    @State private var showsReviewPicker = false
    @State private var reviewTarget: ReviewTarget?
    /// マップで選んでいるお店。評価ボタンの候補の一番上に出す。
    @State private var mapSelection: MKMapItem?
    @State private var pending: MKMapItem?

    var body: some View {
        ZStack {
            tab(.map) { MapHomeView(showsSavedShortcut: false, isActive: selection == .map) }
            tab(.saved) { SavedRestaurantsView(onFindRestaurants: { selection = .map }) }
            tab(.friends) { FriendsHomeView(isActive: selection == .friends, onFindRestaurants: { selection = .map }) }
            tab(.profile) { ProfileView(onFindRestaurants: { selection = .map }) }
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selection, incomingRequestCount: friends.incomingRequests.count) { showsReviewPicker = true }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.floatingTabBarSpace, 80)
        .environment(\.reportsMapSelection) { mapSelection = $0 }
        .sheet(isPresented: $showsReviewPicker, onDismiss: {
            // お店を選んだら、選ぶシートが閉じてから評価のシートを開く。
            if let pending { reviewTarget = ReviewTarget(item: pending); self.pending = nil }
        }) {
            ReviewTargetPicker(mapSelection: mapSelection) { item in
                pending = item
                showsReviewPicker = false
            }
        }
        .sheet(item: $reviewTarget) { QuickRatingSheet(item: $0.item) }
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

/// 評価するお店。シートの item に使うため、識別子を持たせる。
private struct ReviewTarget: Identifiable {
    let id = UUID()
    let item: MKMapItem
}

private struct FloatingTabBarSpaceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct ReportsMapSelectionKey: EnvironmentKey {
    static let defaultValue: ((MKMapItem?) -> Void)? = nil
}

extension EnvironmentValues {
    /// マップで選んでいるお店を、タブバーの評価ボタンに知らせる。
    var reportsMapSelection: ((MKMapItem?) -> Void)? {
        get { self[ReportsMapSelectionKey.self] }
        set { self[ReportsMapSelectionKey.self] = newValue }
    }

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

/// アイコンだけのタブバー。選んだタブの後ろに提灯の灯りがともり、真ん中は評価のボタン。
private struct FloatingTabBar: View {
    @Binding var selection: MainTabView.Tab
    var incomingRequestCount: Int
    var onReview: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.map, title: "マップ", symbol: "map")
            item(.saved, title: "保存", symbol: "heart")
            reviewButton
            item(.friends, title: "友達", symbol: "person.2")
            item(.profile, title: "プロフィール", symbol: "person.crop.circle")
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(Capsule().fill(MeshinowaTheme.card).shadow(color: .black.opacity(0.07), radius: 6, y: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func item(_ tab: MainTabView.Tab, title: String, symbol: String) -> some View {
        let isActive = selection == tab
        return Button {
            selection = tab
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? MeshinowaTheme.green : MeshinowaTheme.ink)
                .frame(width: 30, height: 36)
                .background { LanternLight(isLit: isActive) }
                .overlay(alignment: .topTrailing) {
                    if tab == .friends && incomingRequestCount > 0 {
                        Text(incomingRequestCount > 99 ? "99+" : "\(incomingRequestCount)")
                            .font(MeshinowaFont.number(10, relativeTo: .caption2))
                            .foregroundStyle(MeshinowaTheme.paper)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(MeshinowaTheme.green, in: Capsule())
                            .overlay(Capsule().strokeBorder(MeshinowaTheme.paper, lineWidth: 1.5))
                            .offset(x: 10, y: -5)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(tab == .friends && incomingRequestCount > 0 ? "届いた申請\(incomingRequestCount)件" : "")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// バー（高さ60）より少し大きくし、上下に少しはみ出させる。
    private var reviewButton: some View {
        Button(action: onReview) {
            BowlBadge(size: 62)
                .padding(3)
                .background(Circle().fill(MeshinowaTheme.card))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        }
        .buttonStyle(PressScaleStyle())
        .frame(width: 80)
        .accessibilityLabel("評価を投稿")
        .accessibilityHint("評価するお店を選びます")
    }
}

/// 選んだタブの後ろにともる、提灯の形の灯り。上下に緑の口金を付ける。
/// タブを押すと、その場で提灯がふくらんで灯り、一瞬強く光ってから落ち着く。前のタブの灯りは静かに消える。
private struct LanternLight: View {
    let isLit: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 灯った直後だけ強く光らせる。
    @State private var flare = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(RadialGradient(colors: [Color(red: 1, green: flare ? 0.95 : 0.906, blue: flare ? 0.78 : 0.69),
                                          MeshinowaTheme.lanternLight],
                                 center: .init(x: 0.5, y: 0.45), startRadius: 0, endRadius: flare ? 26 : 20))
            .shadow(color: MeshinowaTheme.lanternGlow.opacity(flare ? 0.9 : 0.45), radius: flare ? 14 : 6)
            .overlay(alignment: .top) { cap.offset(y: -1.5) }
            .overlay(alignment: .bottom) { cap.offset(y: 1.5) }
            // 提灯を広げるように、縦にふくらませて出す。
            .scaleEffect(x: 1, y: isLit || reduceMotion ? 1 : 0.55)
            .opacity(isLit ? 1 : 0)
            .animation(isLit ? .spring(response: 0.32, dampingFraction: 0.62) : .easeOut(duration: 0.15), value: isLit)
            .onChange(of: isLit) { _, lit in
                guard lit, !reduceMotion else { return }
                flare = true
                withAnimation(.easeOut(duration: 0.6).delay(0.12)) { flare = false }
            }
            .accessibilityHidden(true)
    }

    private var cap: some View {
        RoundedRectangle(cornerRadius: 1).fill(MeshinowaTheme.green).frame(width: 15, height: 3)
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
