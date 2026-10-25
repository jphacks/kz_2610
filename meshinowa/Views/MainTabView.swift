import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable, CaseIterable { case map, saved, friends, profile }
    @State private var selection: Tab = .map

    var body: some View {
        ZStack {
            tab(.map) { MapHomeView(showsSavedShortcut: false) }
            tab(.saved) { SavedRestaurantsView(onFindRestaurants: { selection = .map }) }
            tab(.friends) { FriendsHomeView(isActive: selection == .friends) }
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
