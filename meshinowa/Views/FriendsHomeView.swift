import SwiftUI

struct FriendsHomeView: View {
    private enum Section: Hashable { case recommended, feed, connections }
    /// タブが表示中のときだけ、申請や友達の評価を定期的に取り直す。
    var isActive = true
    @EnvironmentObject private var store: FriendStore
    @State private var section: Section = .recommended

    /// サーバー未設定ならデモのまま。接続できればゲストの実データを出す。
    private var dataset: FriendDataset {
        store.isAvailable ? store.dataset : DemoRecommendations.dataset
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: "友達")
                    .padding(.horizontal, 20)
                UnderlineTabs(items: tabs, selection: $section)
                    .padding(.horizontal, 20)

                if case .failed(let message) = store.status {
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
        .refreshable { await store.refresh() }
        .task(id: isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var tabs: [UnderlineTabs<Section>.Item] {
        var items: [UnderlineTabs<Section>.Item] = [
            .init(value: .recommended, title: "おすすめ"),
            .init(value: .feed, title: "フィード")
        ]
        if store.isAvailable {
            let incoming = store.incomingRequests.count
            items.append(.init(value: .connections, title: "つながり", badge: incoming > 0 ? "\(incoming)" : nil))
        }
        return items
    }

    private var recommended: some View {
        VStack(alignment: .leading, spacing: 24) {
            NavigationLink {
                FriendMapScreen(isDemo: !store.isAvailable)
            } label: {
                banner
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            if store.isAvailable && store.friends.isEmpty {
                Button { section = .connections } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("まずは友達とつながろう")
                            .font(MeshinowaFont.heading(17))
                        Text("「つながり」で自分のIDを伝えるか、友達のIDで申請できます。")
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
                        if dataset.isDemo { SoftTag(text: "架空", tone: .neutral, compact: true) }
                    }
                    .padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(dataset.latestReviews.prefix(6)) { review in
                                NavigationLink {
                                    FriendMapScreen(isDemo: dataset.isDemo, initialSelection: review.restaurantID)
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

            if store.isAvailable {
                NavigationLink { DemoRecommendationsView() } label: {
                    Label("架空データのデモを見る", systemImage: "sparkles")
                        .font(MeshinowaFont.text(14, weight: .bold))
                        .foregroundStyle(MeshinowaTheme.green)
                }
                .padding(.horizontal, 20)
            } else {
                Text("サーバーに接続していないため、ここに出る友達・店舗・レビューはすべて架空です。")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                    .padding(.horizontal, 20)
            }
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
                Text(dataset.isDemo ? "架空の友達の評価で試せます。"
                     : "友達\(dataset.friends.count)人・\(dataset.restaurants.count)軒の評価")
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.bodyText)
                HStack(spacing: 4) {
                    Text(dataset.isDemo ? "架空データで試す" : "友達のおすすめマップ")
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
        .accessibilityHint("友達の評価マップを開きます")
    }

    private var feed: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(dataset.isDemo ? "架空の友達の記録" : "友達の記録")
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                Spacer()
            }
            .padding(.vertical, 12)
            if dataset.latestReviews.isEmpty {
                Text("友達の記録はまだありません。友達がお店を評価すると、ここに新しい順で並びます。")
                    .font(MeshinowaFont.text(14))
                    .foregroundStyle(MeshinowaTheme.bodyText)
            }
            ForEach(dataset.latestReviews) { review in
                let restaurant = dataset.restaurant(review.restaurantID)
                let name = dataset.friendName(review.friendID)
                NavigationLink {
                    FriendMapScreen(isDemo: dataset.isDemo, initialSelection: review.restaurantID)
                } label: {
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
                            if !review.comment.isEmpty {
                                Text("「\(review.comment)」")
                                    .font(MeshinowaFont.text(14))
                                    .foregroundStyle(MeshinowaTheme.bodyText)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// 友達のおすすめマップ。実データは開いている間も最新の状態を反映する。
private struct FriendMapScreen: View {
    let isDemo: Bool
    var initialSelection: String? = nil
    @EnvironmentObject private var store: FriendStore

    var body: some View {
        DemoRecommendationsView(dataset: isDemo ? DemoRecommendations.dataset : store.dataset,
                                initialSelection: initialSelection)
    }
}

/// 自分のID・申請・友達一覧。
private struct FriendConnectionsSection: View {
    @EnvironmentObject private var store: FriendStore
    @State private var handle = ""
    @State private var message: String?
    @State private var isSending = false
    @State private var editsName = false
    @State private var name = ""
    @State private var removing: FriendStore.Friend?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            myCard
            addFriend
            if !store.incomingRequests.isEmpty {
                group("届いた申請") {
                    ForEach(store.incomingRequests) { request in
                        personRow(name: request.fromName, handle: request.fromHandle) {
                            HStack(spacing: 8) {
                                Button("見送る") { Task { await store.respond(to: request, accept: false) } }
                                    .buttonStyle(PillButtonStyle(isOn: false))
                                Button("承認") { Task { await store.respond(to: request, accept: true) } }
                                    .buttonStyle(PillButtonStyle(isOn: true))
                            }
                        }
                    }
                }
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
            group("友達 \(store.friends.count)人") {
                if store.friends.isEmpty {
                    Text("まだ友達はいません。")
                        .font(MeshinowaFont.text(14))
                        .foregroundStyle(MeshinowaTheme.bodyText)
                }
                ForEach(store.friends) { friend in
                    let isFavorite = friend.isFavorite != 0
                    personRow(name: friend.displayName, handle: friend.handle) {
                        Button {
                            Task { await store.setFavorite(friend, !isFavorite) }
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .foregroundStyle(isFavorite ? MeshinowaTheme.accent : MeshinowaTheme.secondaryText)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("お気に入りの友達")
                        .accessibilityValue(isFavorite ? "登録済み" : "未登録")
                    }
                    .contextMenu {
                        Button("友達を解除", role: .destructive) { removing = friend }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .alert("名前を変更", isPresented: $editsName) {
            TextField("表示名", text: $name)
            Button("キャンセル", role: .cancel) {}
            Button("保存") { Task { _ = await store.rename(name) } }
        } message: { Text("友達に表示される名前です（40文字まで）。") }
        .confirmationDialog("友達を解除しますか？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("解除する", role: .destructive) {
                if let removing { Task { await store.remove(removing) } }
            }
        } message: { Text("お互いの評価が見えなくなります。") }
    }

    private var myCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                FriendAvatar(name: store.me?.displayName ?? "ゲスト", size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.me?.displayName ?? "接続中…")
                        .font(MeshinowaFont.heading(18))
                    Text(store.me.map { "ID: \($0.handle)" } ?? "")
                        .font(MeshinowaFont.number(15, relativeTo: .body))
                        .foregroundStyle(MeshinowaTheme.bodyText)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button {
                    name = store.me?.displayName ?? ""
                    editsName = true
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("名前を変更")
                    .disabled(store.me == nil)
            }
            if let me = store.me {
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = me.handle
                        message = "IDをコピーしました。"
                    } label: { Label("IDをコピー", systemImage: "doc.on.doc") }
                        .buttonStyle(PaperButtonStyle(kind: .secondary))
                    ShareLink(item: "meshinowaで友達になろう！ ID: \(me.handle)") {
                        Label("IDを送る", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PaperButtonStyle(kind: .secondary))
                }
            }
            Text("ゲストとして利用中です。このIDはこの端末だけのもので、アプリを削除すると戻せない場合があります。")
                .font(MeshinowaFont.text(12, relativeTo: .caption))
                .foregroundStyle(MeshinowaTheme.secondaryText)
        }
        .padding(16)
        .paperCard()
    }

    private var addFriend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IDで友達を追加")
                .font(MeshinowaFont.heading(18))
            HStack(spacing: 10) {
                TextField("友達のID", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(MeshinowaFont.text(16))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(MeshinowaTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .submitLabel(.send)
                    .onSubmit(send)
                Button("申請", action: send)
                    .buttonStyle(PaperButtonStyle())
                    .frame(width: 96)
                    .disabled(isSending || handle.trimmingCharacters(in: .whitespaces).isEmpty || store.me == nil)
            }
            if let message {
                Text(message)
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.bodyText)
            }
        }
    }

    private func send() {
        guard !isSending else { return }
        isSending = true
        Task {
            if let error = await store.sendRequest(handle: handle) {
                message = error
            } else {
                message = "申請を送りました。相手が承認すると友達になります。"
                handle = ""
            }
            isSending = false
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(MeshinowaFont.heading(18))
            content()
        }
    }

    private func personRow<Trailing: View>(name: String, handle: String,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            FriendAvatar(name: name, size: 40)
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
