import SwiftUI

struct MainTabView: View {
    private enum Tab: Hashable { case map, saved, friends, profile }
    @State private var selection: Tab = .map

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { MapHomeView(showsSavedShortcut: false) }
                .tabItem { Label("マップ", systemImage: "map") }
                .tag(Tab.map)
            NavigationStack { SavedRestaurantsView(onFindRestaurants: { selection = .map }) }
                .tabItem { Label("保存", systemImage: "bookmark") }
                .tag(Tab.saved)
            NavigationStack { FriendsHomeView() }
                .tabItem { Label("友達", systemImage: "person.2") }
                .tag(Tab.friends)
            NavigationStack { ProfileView(onFindRestaurants: { selection = .map }) }
                .tabItem { Label("プロフィール", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .toolbarBackground(MeshinowaTheme.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct FriendsHomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("友達のおすすめを、あなたの地図に。")
                    .font(MeshinowaFont.text(24, weight: .black, relativeTo: .title2))
                VStack(alignment: .leading, spacing: 12) {
                    Label("友達との接続は準備中です", systemImage: "person.2")
                        .font(MeshinowaFont.text(17, weight: .black, relativeTo: .headline))
                    Text("ログインと申請・承認の機能は、今後追加します。現在のレビューはこの端末だけの記録です。")
                        .font(MeshinowaFont.text(14))
                }
                .padding(18)
                .paperCard()
                NavigationLink {
                    DemoRecommendationsView()
                } label: {
                    Text("架空データでFriend Lensを試す")
                }
                .buttonStyle(PaperButtonStyle())
                Text("デモの友達・店舗・レビューはすべて架空です。自分の記録とは分けています。")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .navigationTitle("友達")
    }
}
