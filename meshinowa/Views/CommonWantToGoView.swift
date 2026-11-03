import SwiftUI

struct CommonWantToGoView: View {
    let friend: FriendStore.Friend
    @EnvironmentObject private var store: FriendStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var result: CommonWantToGoResult?
    @State private var error: String?
    @State private var busy = false
    @State private var selected: CommonWantToGoResult.Restaurant?
    @State private var showsConsent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(friend.displayName)さんと一緒に")
                    .font(MeshinowaFont.heading(24))
                Text("2人とも「行きたい」に入れたお店")
                    .font(MeshinowaFont.text(14)).foregroundStyle(MeshinowaTheme.bodyText)
                if busy { ProgressView("共通のお店を確認しています…") }
                if let error {
                    state("読み込めませんでした", error)
                    Button("もう一度読み込む") { Task { await load() } }.buttonStyle(PaperButtonStyle())
                } else if let result {
                    content(result)
                }
            }.padding(20)
        }
        .background(MeshinowaTheme.ground).foregroundStyle(MeshinowaTheme.ink)
        .font(MeshinowaFont.text(15))
        .navigationTitle("一緒に行きたいお店").navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: scenePhase) {
            result = nil; selected = nil
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: store.friends.map(\.id)) { _, ids in
            if !ids.contains(friend.id) { result = .init(state: "not_friend", restaurants: []); selected = nil }
        }
        .onChange(of: store.me?.id) { _, _ in result = nil; selected = nil }
        .sheet(item: $selected) { restaurant in RestaurantInformationView(item: restaurant.mapItem) }
        .confirmationDialog("行きたいを友達と共有しますか？", isPresented: $showsConsent, titleVisibility: .visible) {
            Button("共有をオンにする") { Task { await enableSharing() } }
        } message: {
            Text("共有をオンにしている友達全員と、共通のお店だけがお互いに見えるようになります。「行きたい」の一覧全体や「いいね」は見えません。設定からいつでもオフにできます。")
        }
    }

    @ViewBuilder private func content(_ result: CommonWantToGoResult) -> some View {
        switch result.state {
        case "self_off":
            state("2人とも行きたいお店を見つけよう", "共有をオンにすると、同じくオンにしている友達との共通のお店が見られます。")
            Button("共有の説明を見る") { showsConsent = true }.buttonStyle(PaperButtonStyle()).disabled(busy)
        case "partner_off":
            state("相手は「行きたい」を共有していません", "相手も共有をオンにすると、共通のお店が表示されます。")
        case "not_friend":
            state("この一覧は表示できません", "友達関係が変更された可能性があります。")
        case "ok":
            if result.restaurants.isEmpty {
                state("共通のお店はまだありません", "お店の旗を押して「行きたい」に入れると、友達も入れていた場合にここに表示されます。")
            } else {
                Text("\(result.restaurants.count)軒").font(MeshinowaFont.text(14, weight: .bold))
                ForEach(result.restaurants) { restaurant in
                    HStack(spacing: 12) {
                        Button { selected = restaurant } label: {
                            HStack(spacing: 12) {
                                FoodGenreMark(genre: FoodGenre.infer(name: restaurant.name, category: restaurant.category), size: 40)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(restaurant.name).font(MeshinowaFont.text(16, weight: .bold))
                                    Label("2人とも行きたい", systemImage: "flag.fill")
                                        .font(MeshinowaFont.text(12)).foregroundStyle(MeshinowaTheme.green)
                                }
                                Spacer(minLength: 0)
                            }
                        }.buttonStyle(.plain)
                        ShareLink(item: RestaurantSharing.message(for: restaurant.mapItem, invitation: true)) {
                            Text("誘う").font(MeshinowaFont.text(14, weight: .bold))
                        }.buttonStyle(PillButtonStyle(isOn: false))
                    }
                    .padding(16).background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MeshinowaTheme.hairline))
                }
                Text("この一覧は、あなたと\(friend.displayName)さんにだけ表示されます。")
                    .font(MeshinowaFont.text(12)).foregroundStyle(MeshinowaTheme.secondaryText)
            }
        default:
            state("表示できませんでした", "アプリを更新して、もう一度お試しください。")
        }
    }

    private func state(_ title: String, _ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.fill").foregroundStyle(MeshinowaTheme.green)
                .frame(width: 64, height: 64).background(MeshinowaTheme.mint, in: Circle())
            Text(title).font(MeshinowaFont.heading(19)).multilineTextAlignment(.center)
            Text(message).font(MeshinowaFont.text(14)).foregroundStyle(MeshinowaTheme.bodyText).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
    private func load() async {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        let identity = store.me?.id
        defer { busy = false }
        do {
            // 端末内で変更した「行きたい」を先に同期する。
            await SwipeDiscoveryEntry.refreshWantToGo(reviewedIDs: PersonalLibrary.reviewedKeys(reviews.reviews))
            let value = try await store.commonWantToGo(friendID: friend.id)
            guard !Task.isCancelled, identity == store.me?.id, scenePhase == .active else { return }
            result = value
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "通信状態を確認して、もう一度お試しください。"
        }
    }
    private func enableSharing() async {
        busy = true; error = nil
        do { try await store.updateWantToGoSharing(true); busy = false; await load() }
        catch { busy = false; self.error = "共有設定を保存できませんでした。" }
    }
}
