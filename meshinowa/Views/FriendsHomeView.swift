import SwiftUI

struct FriendsHomeView: View {
    private enum Section: Hashable { case recommended, feed, connections }
    /// タブが表示中のときだけ、申請や友達の評価を定期的に取り直す。
    var isActive = true
    var onFindRestaurants: (() -> Void)? = nil
    @EnvironmentObject private var store: FriendStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: Section = .recommended
    @State private var showsAddFriend = false

    /// 接続状態にかかわらず、取得済みの実データだけを表示する。
    private var dataset: FriendDataset {
        store.dataset
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ScreenTitle(text: "友達")
                    Spacer()
                    Button { showsAddFriend = true } label: {
                        Label("追加", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(PillButtonStyle(isOn: false))
                    .accessibilityIdentifier("friends.add")
                }
                .padding(.horizontal, 20)
                UnderlineTabs(items: tabs, selection: $section)
                    .padding(.horizontal, 20)

                if case .failed(let message) = store.status, !(isDisconnected && section == .recommended) {
                    Text(message)
                        .font(MeshinowaFont.text(13, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.bodyText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MeshinowaTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                switch section {
                case .recommended: recommended
                case .feed: feed
                case .connections: FriendConnectionsSection()
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await store.retryConnection() }
        .task(id: isActive && scenePhase == .active) {
            guard isActive && scenePhase == .active else { return }
            await store.refreshIfNeeded()
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsAddFriend) { FriendAddSheet() }
        .alert("変更できませんでした", isPresented: Binding(
            get: { store.actionError != nil },
            set: { if !$0 { store.actionError = nil } }
        )) {
            Button("閉じる", role: .cancel) { store.actionError = nil }
        } message: { Text(store.actionError ?? "もう一度お試しください。") }
    }

    private var tabs: [UnderlineTabs<Section>.Item] {
        var items: [UnderlineTabs<Section>.Item] = [
            .init(value: .recommended, title: "おすすめ"),
            .init(value: .feed, title: "フィード")
        ]
        if store.isAvailable {
            let incoming = store.incomingRequests.count
            items.append(.init(value: .connections, title: "友達 \(store.friends.count)", badge: incoming > 0 ? "\(incoming)" : nil))
        }
        return items
    }

    /// 友達の機能につながっていない、またはつながりに失敗したとき。
    private var isDisconnected: Bool {
        if !store.isAvailable { return true }
        if case .failed = store.status { return dataset.latestReviews.isEmpty }
        return false
    }

    /// つながっていないときの空の状態。ほかの画面と同じ形（ミントの丸・見出し・主ボタン・副ボタン）。
    private var disconnected: some View {
        VStack(spacing: 12) {
            BowlMark(size: 52, holes: MeshinowaTheme.mint)
                .frame(width: 84, height: 84)
                .background(MeshinowaTheme.mint, in: Circle())
            Text("友達の機能に\nつながっていません")
                .font(MeshinowaFont.heading(18))
                .multilineTextAlignment(.center)
            Text(store.isAvailable ? "通信を確かめて、もう一度試してください。\n地図のお店探しは、このままでも使えます。"
                 : "このアプリには、友達の機能の接続先が設定されていません。\n地図のお店探しは、このままでも使えます。")
                .font(MeshinowaFont.text(14))
                .foregroundStyle(MeshinowaTheme.bodyText)
                .multilineTextAlignment(.center)
            if store.isAvailable {
                Button("もう一度つなぐ") { Task { await store.retryConnection() } }
                    .buttonStyle(PaperButtonStyle())
                    .padding(.top, 4)
            }
            if let onFindRestaurants {
                Button("マップでお店を探す", action: onFindRestaurants)
                    .buttonStyle(PaperButtonStyle(kind: store.isAvailable ? .secondary : .primary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 36)
    }

    @ViewBuilder private var recommended: some View {
        if isDisconnected {
            disconnected
        } else {
            connectedRecommendations
        }
    }

    private var connectedRecommendations: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 10) {
                banner
                if !dataset.ratedRestaurants.isEmpty {
                    NavigationLink {
                        FriendMapScreen()
                    } label: {
                        mapEntry
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            if store.isAvailable && store.friends.isEmpty {
                Button { showsAddFriend = true } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("まずは友達とつながろう")
                            .font(MeshinowaFont.heading(17))
                        Text("「追加」から自分のIDを伝えるか、友達のIDで申請できます。")
                            .font(MeshinowaFont.text(14))
                            .foregroundStyle(MeshinowaTheme.bodyText)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .paperCard()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }

            if !dataset.latestReviews.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("友達の最近の記録")
                            .font(MeshinowaFont.heading(20))
                    }
                    .padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(dataset.latestReviews.prefix(6)) { review in
                                NavigationLink {
                                    FriendMapScreen(initialSelection: review.restaurantID)
                                } label: {
                                    RecentReviewCard(review: review, dataset: dataset)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }

            if store.isAvailable && !store.friends.isEmpty && dataset.latestReviews.isEmpty {
                Text("友達の評価はまだありません。友達がお店を評価すると、ここに表示されます。")
                    .font(MeshinowaFont.text(14))
                    .foregroundStyle(MeshinowaTheme.bodyText)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 18)
    }

    /// 小さな帯。友達の記録を上に見せるため、案内は短くする。
    private var banner: some View {
        HStack(spacing: 12) {
            BowlMark(size: 44, holes: MeshinowaTheme.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("友達の「うまい」を地図に集めよう")
                    .font(MeshinowaFont.heading(16))
                    .fixedSize(horizontal: false, vertical: true)
                Text(store.isAvailable ? "友達\(dataset.friends.count)人・\(dataset.restaurants.count)軒の評価"
                     : "友達の機能は現在利用できません。")
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.bodyText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MeshinowaTheme.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 友達のおすすめマップへの入口。1行で目立たせる。
    private var mapEntry: some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MeshinowaTheme.green)
                .frame(width: 36, height: 36)
                .background(MeshinowaTheme.mint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("友達のおすすめを地図で見る")
                .font(MeshinowaFont.text(15, weight: .bold))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MeshinowaTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MeshinowaTheme.hairline))
        .contentShape(Rectangle())
        .accessibilityHint("友達の評価マップを開きます")
    }

    private var feed: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            // フィードはお店スワイプ専用。友達の記録のタイムラインは出さない。
            SwipeDiscoveryEntry.feedBanner()
        }
        .padding(.horizontal, 20)
    }
}

/// 友達のおすすめマップ。実データは開いている間も最新の状態を反映する。
private struct FriendMapScreen: View {
    var initialSelection: String? = nil
    @EnvironmentObject private var store: FriendStore

    var body: some View {
        FriendRecommendationsView(dataset: store.dataset,
                                initialSelection: initialSelection)
    }
}

/// 自分のID・申請・友達一覧。
private struct FriendConnectionsSection: View {
    @EnvironmentObject private var store: FriendStore
    @State private var removing: FriendStore.Friend?
    @State private var blockingID: String?
    @State private var selectedProfile: FriendStore.Friend?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !store.incomingRequests.isEmpty {
                group("申請が届いています") {
                    ForEach(store.incomingRequests) { request in
                        personRow(name: request.fromName, handle: request.fromHandle) {
                            HStack(spacing: 8) {
                                Button("見送る") { Task { await store.respond(to: request, accept: false) } }
                                    .buttonStyle(PillButtonStyle(isOn: false))
                                Button("承認") { Task { await store.respond(to: request, accept: true) } }
                                    .buttonStyle(PillButtonStyle(isOn: true))
                            }
                        }
                        .contextMenu { Button("ブロック", role: .destructive) { blockingID = request.fromId } }
                    }
                }
                .padding(16)
                .background(MeshinowaTheme.mint, in: RoundedRectangle(cornerRadius: 18))
            }
            if !store.outgoingRequests.isEmpty {
                group("送った申請") {
                    ForEach(store.outgoingRequests) { request in
                        personRow(name: request.toName, handle: request.toHandle) {
                            Button("取り消す") { Task { await store.cancel(request) } }
                                .buttonStyle(PillButtonStyle(isOn: false))
                        }
                    }
                }
            }
            if store.friends.isEmpty {
                Text("まだ友達はいません。右上の「追加」から友達とつながれます。")
                    .font(MeshinowaFont.text(14))
                    .foregroundStyle(MeshinowaTheme.bodyText)
            }
            ForEach([true, false], id: \.self) { favorite in
                let people = store.friends.filter { ($0.isFavorite != 0) == favorite }
                if !people.isEmpty {
                    group(favorite ? "お気に入りの友達" : "ほかの友達") {
                        ForEach(people) { friend in
                            personRow(name: friend.displayName, handle: friend.handle, symbol: friend.avatarSymbol) {
                                Button { selectedProfile = friend } label: {
                                    Image(systemName: "chevron.right")
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(friend.displayName)のプロフィール")
                                Button {
                                    Task { await store.setFavorite(friend, !favorite) }
                                } label: {
                                    Image(systemName: favorite ? "star.fill" : "star")
                                        .foregroundStyle(MeshinowaTheme.green)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("お気に入りの友達")
                                .accessibilityValue(favorite ? "登録済み" : "未登録")
                            }
                            .contextMenu {
                                Button("プロフィールを見る") { selectedProfile = friend }
                                Button("ブロック", role: .destructive) { blockingID = friend.id }
                                Button("友達を解除", role: .destructive) { removing = friend }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .sheet(item: $selectedProfile) { friend in
            NavigationStack {
                VStack(spacing: 18) {
                    ProfileIcon(symbol: friend.avatarSymbol ?? "person.fill", size: 88)
                    Text(friend.displayName).font(MeshinowaFont.heading(26))
                    Text("ID: \(friend.handle)").font(MeshinowaFont.text(14))
                    Text(friend.bio ?? "").font(MeshinowaFont.text(16)).multilineTextAlignment(.center)
                    Spacer()
                }.padding(24).frame(maxWidth: .infinity).background(MeshinowaTheme.paper)
                    .navigationTitle("友達のプロフィール").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { selectedProfile = nil } } }
            }.presentationDetents([.medium, .large])
        }
        .confirmationDialog("この人をブロックしますか？", isPresented: Binding(get: { blockingID != nil }, set: { if !$0 { blockingID = nil } }), titleVisibility: .visible) {
            Button("ブロックする", role: .destructive) {
                if let id = blockingID { Task { await store.block(id) } }
                blockingID = nil
            }
        } message: { Text("お互いのプロフィールと評価が見えなくなり、友達関係と申請は解除されます。") }
        .confirmationDialog("友達を解除しますか？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("解除する", role: .destructive) {
                if let removing { Task { await store.remove(removing) } }
            }
        } message: { Text("お互いの評価が見えなくなります。") }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(MeshinowaFont.heading(18))
            content()
        }
    }

    private func personRow<Trailing: View>(name: String, handle: String, symbol: String? = nil,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            FriendAvatar(name: name, size: 40, symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(MeshinowaFont.text(15, weight: .bold))
                Text("ID: \(handle)")
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
    }
}

private struct RecentReviewCard: View {
    let review: FriendReview
    let dataset: FriendDataset

    var body: some View {
        let restaurant = dataset.restaurant(review.restaurantID)
        let name = dataset.friendName(review.friendID)
        VStack(alignment: .leading, spacing: 8) {
            // 写真の代わりに、ジャンルの器の形（地図のピンと同じ）を出す。
            FoodGenreMark(genre: FoodGenre.infer(name: restaurant.map { "\($0.name) \($0.genre)" }, category: restaurant?.category), size: 56)
                .frame(width: 200, height: 120)
                .background(MeshinowaTheme.photo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

/// IDの共有と申請を一か所にまとめる。検索は明示操作時だけ完全一致で行う。
private struct FriendAddSheet: View {
    @EnvironmentObject private var store: FriendStore
    @Environment(\.dismiss) private var dismiss
    @State private var handle = ""
    @State private var result: FriendStore.Profile?
    @State private var message: String?
    @State private var isSearching = false
    @State private var isSending = false
    @State private var sentID: String?
    @FocusState private var focusesID: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 12) {
                        step(1, "IDを送るか\nIDで申請")
                        step(2, "相手が\n承認する")
                        step(3, "お互いの評価が\n地図に出る")
                    }
                    myID
                    if store.isAvailable {
                        search
                    } else {
                        Text("友達の機能につながっていません。接続後にIDの共有と申請ができます。")
                            .font(MeshinowaFont.text(14))
                            .foregroundStyle(MeshinowaTheme.bodyText)
                    }
                    if let message {
                        Text(message)
                            .font(MeshinowaFont.text(14))
                            .foregroundStyle(MeshinowaTheme.bodyText)
                            .accessibilityIdentifier("friends.add.message")
                    }
                    Text("送った申請の取り消しや、届いた申請の承認は「友達」タブでできます。")
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MeshinowaTheme.paper)
            .foregroundStyle(MeshinowaTheme.ink)
            .navigationTitle("友達を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await store.refreshIfNeeded() }
        }
        .tint(MeshinowaTheme.green)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        VStack(spacing: 8) {
            Text("\(number)")
                .font(MeshinowaFont.number(16, relativeTo: .body))
                .frame(width: 30, height: 30)
                .foregroundStyle(number == 1 ? MeshinowaTheme.paper : MeshinowaTheme.green)
                .background(number == 1 ? MeshinowaTheme.green : MeshinowaTheme.mint, in: Circle())
            Text(text)
                .font(MeshinowaFont.text(12, relativeTo: .caption))
                .multilineTextAlignment(.center)
                .foregroundStyle(MeshinowaTheme.bodyText)
        }
        .frame(maxWidth: .infinity)
    }

    private var myID: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("あなたのID").font(MeshinowaFont.text(14, weight: .bold))
            if let me = store.me {
                Text("@\(me.handle)")
                    .font(MeshinowaFont.number(30, relativeTo: .title))
                    .textSelection(.enabled)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    ShareLink(item: "メシノワで友達になろう！ ID: @\(me.handle)") {
                        Label("IDを送る", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PaperButtonStyle())
                    Button {
                        UIPasteboard.general.string = me.handle
                        message = "IDをコピーしました。"
                    } label: { Label("コピー", systemImage: "doc.on.doc") }
                    .buttonStyle(PaperButtonStyle(kind: .secondary))
                }
                Text("このIDはこの端末のものです。アプリを削除すると戻せない場合があります。")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
            } else if store.isAvailable {
                Text("IDを取得できていません。接続を確認して再試行してください。")
                    .font(MeshinowaFont.text(14))
                Button("もう一度つなぐ") { Task { await store.retryConnection() } }
                    .buttonStyle(PaperButtonStyle(kind: .secondary))
            } else {
                Text("接続後に表示されます").font(MeshinowaFont.text(14))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeshinowaTheme.field, in: RoundedRectangle(cornerRadius: 22))
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("友達のIDで申請する").font(MeshinowaFont.text(15, weight: .bold))
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(MeshinowaTheme.secondaryText)
                TextField("@友達のID（完全一致）", text: $handle)
                    .font(MeshinowaFont.text(16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focusesID)
                    .onSubmit(lookup)
                    .onChange(of: handle) { _, _ in result = nil; message = nil }
                    .disabled(isSearching || isSending)
                    .accessibilityIdentifier("friends.add.handle")
                Button(action: lookup) {
                    if isSearching { ProgressView() } else { Text("検索") }
                }
                .font(MeshinowaFont.text(14, weight: .bold))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.me == nil || isSearching || isSending)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MeshinowaTheme.green))
            if let profile = result {
                HStack(spacing: 12) {
                    FriendAvatar(name: profile.displayName, size: 44, symbol: profile.avatarSymbol)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName).font(MeshinowaFont.text(16, weight: .bold))
                        Text("@\(profile.handle)")
                            .font(MeshinowaFont.text(13, relativeTo: .caption))
                            .foregroundStyle(MeshinowaTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if profile.id == store.me?.id {
                        stateLabel("自分")
                    } else if store.friends.contains(where: { $0.id == profile.id }) {
                        stateLabel("友達")
                    } else if store.incomingRequests.contains(where: { $0.fromId == profile.id }) {
                        stateLabel("申請あり")
                    } else if sentID == profile.id || store.outgoingRequests.contains(where: { $0.toId == profile.id }) {
                        stateLabel("申請中")
                    } else {
                        Button(isSending ? "送信中" : "申請する") { send(profile) }
                            .buttonStyle(PillButtonStyle(isOn: true))
                            .disabled(isSending)
                    }
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
            }
        }
    }

    private func stateLabel(_ text: String) -> some View {
        Text(text)
            .font(MeshinowaFont.text(13, weight: .bold))
            .foregroundStyle(MeshinowaTheme.bodyText)
            .padding(12)
            .background(MeshinowaTheme.field, in: Capsule())
    }

    private func lookup() {
        guard !isSearching && !isSending && store.me != nil else { return }
        focusesID = false
        isSearching = true
        result = nil
        message = nil
        Task {
            defer { isSearching = false }
            do {
                result = try await store.findProfile(handle: handle)
                if result == nil { message = "そのIDの人が見つかりませんでした。IDを確認してください。" }
            } catch let error as FriendStore.ProfileSearchError {
                message = error.localizedDescription
            } catch {
                message = "検索できませんでした。通信を確認して、もう一度お試しください。"
            }
        }
    }

    private func send(_ profile: FriendStore.Profile) {
        guard !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            if let error = await store.sendRequest(to: profile) {
                message = error
            } else {
                sentID = profile.id
                message = "申請を送りました。相手が承認すると友達になります。"
            }
        }
    }
}
