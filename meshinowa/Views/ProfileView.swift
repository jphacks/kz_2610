import SwiftUI

struct ProfileView: View {
    var onFindRestaurants: () -> Void
    @EnvironmentObject private var reviews: LocalReviewStore
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var friends: FriendStore
    @EnvironmentObject private var transfer: LibraryTransfer
    @AppStorage("profile.name") private var localName = "ゲスト"
    @AppStorage("profile.bio") private var localBio = ""
    @AppStorage("profile.symbol") private var localSymbol = "person.fill"
    @State private var editing: LocalReview?
    @State private var editsProfile = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    ScreenTitle(text: "プロフィール")
                    Spacer()
                    NavigationLink { SWAccountSettingsView() } label: { Image(systemName: "gearshape") }
                        .buttonStyle(CircleIconButtonStyle())
                        .accessibilityLabel("設定を開く")
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        ProfileIcon(symbol: friends.me?.avatarSymbol ?? localSymbol, size: 68)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(friends.me?.displayName ?? localName).font(MeshinowaFont.heading(24))
                            if let me = friends.me {
                                Text("ID: \(me.handle)").font(MeshinowaFont.text(13)).textSelection(.enabled)
                            } else {
                                Text(friends.connectionLabel)
                                    .font(MeshinowaFont.text(13)).foregroundStyle(MeshinowaTheme.secondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    let bio = friends.me?.bio ?? localBio
                    if !bio.isEmpty { Text(bio).font(MeshinowaFont.text(15)).fixedSize(horizontal: false, vertical: true) }
                    Button("プロフィールを編集") { editsProfile = true }
                        .buttonStyle(PaperButtonStyle(kind: .secondary))
                        .disabled(friends.isAvailable && friends.me == nil)
                    if let me = friends.me {
                        ShareLink(item: "meshinowaで友達になろう！ ID: \(me.handle)") {
                            Label("友達にIDを送る", systemImage: "square.and.arrow.up")
                        }.font(MeshinowaFont.text(14, weight: .bold))
                    }
                }
                .padding(20).paperCard()
                if case .failed(let message) = friends.status {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(message).font(MeshinowaFont.text(14))
                        Button("再読み込み") { Task { await friends.retryConnection() } }
                            .buttonStyle(PaperButtonStyle(kind: .secondary))
                    }.padding(16).paperCard()
                }
                HStack(spacing: 0) {
                    statistic("行った", count: reviews.reviews.count) { Image(systemName: "star.fill").foregroundStyle(MeshinowaTheme.accent) }
                    divider
                    statistic("いいね", count: saved.restaurants.filter(\.isLiked).count) { Image(systemName: "heart.fill").foregroundStyle(MeshinowaTheme.like) }
                    divider
                    statistic("友達", count: friends.friends.count) { Image(systemName: "person.2.fill").foregroundStyle(MeshinowaTheme.green) }
                }.padding(.vertical, 16).paperCard()

                if friends.isAvailable && !reviews.pending.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("友達への共有待ち \(reviews.pending.count)件", systemImage: "arrow.triangle.2.circlepath")
                        if let error = friends.syncError { Text(error).font(MeshinowaFont.text(13)) }
                        Button("今すぐ再試行") { Task { await friends.flushReviews() } }
                    }.font(MeshinowaFont.text(14)).padding(16).paperCard()
                }
                genreShelf

                VStack(spacing: 0) {
                    NavigationLink { MyReviewsView(onFindRestaurants: onFindRestaurants) } label: {
                        linkRow("自分のレビュー一覧", symbol: "text.bubble")
                    }
                    NavigationLink { MyRestaurantMapView(onFindRestaurants: onFindRestaurants) } label: {
                        linkRow("マイマップ", symbol: "map")
                    }
                    if friends.isAvailable {
                        NavigationLink { SWAccountSettingsView() } label: {
                            linkRow("公開設定・データの引き継ぎ", symbol: "person.crop.circle.badge.checkmark")
                        }
                    }
                }.buttonStyle(.plain)
                if let error = reviews.loadError {
                    Text(error).font(MeshinowaFont.text(14))
                    Button("レビューを再読み込み") { reviews.reload() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近のレビュー").font(MeshinowaFont.heading(20, relativeTo: .title2))
                    if reviews.reviews.isEmpty && reviews.loadError == nil {
                        Text("まだレビューがありません。お店の詳細から星だけでも記録できます。")
                            .font(MeshinowaFont.text(14)).padding(.top, 6)
                    }
                    ForEach(Array(reviews.reviews.prefix(3))) { review in
                        LocalReviewRow(review: review) { editing = review }
                    }
                }
                Text(friends.isAvailable
                     ? "評価・ひとこと・おすすめ料理は友達に共有されます。写真と来店日は友達に公開されません。設定から自分専用のバックアップを作れます。"
                     : "記録はこの端末だけに保存されます。アプリを削除すると端末内のデータも消えます。")
                    .font(MeshinowaFont.text(12, relativeTo: .caption)).foregroundStyle(MeshinowaTheme.secondaryText)
            }.padding(20)
        }
        .refreshable { await friends.retryConnection() }
        .background(MeshinowaTheme.paper).foregroundStyle(MeshinowaTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { ReviewEditor(item: $0.restaurant.mapItem, existing: $0) }
        .sheet(isPresented: $editsProfile) { ProfileEditorView() }
    }

    private var divider: some View {
        Rectangle().fill(MeshinowaTheme.hairline).frame(width: 1, height: 40)
    }

    /// レビューしたお店を、ジャンルの器の形で数える。まだ行っていないジャンルは薄く出し、集める楽しさを作る。
    private var genreShelf: some View {
        let counts = Dictionary(grouping: reviews.reviews, by: { $0.restaurant.foodGenre }).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 10) {
            Text("よく行くジャンル")
                .font(MeshinowaFont.heading(20, relativeTo: .title2))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(FoodGenre.allCases.filter { $0 != .other }) { genre in
                        let count = counts[genre] ?? 0
                        VStack(spacing: 3) {
                            FoodGenreMark(genre: genre, tone: count > 0 ? .mine : .faint, size: 38)
                            Text("\(count)")
                                .font(MeshinowaFont.number(15, relativeTo: .caption))
                                .foregroundStyle(count > 0 ? MeshinowaTheme.ink : MeshinowaTheme.secondaryText)
                            Text(genre.title)
                                .font(MeshinowaFont.text(11, relativeTo: .caption2))
                                .foregroundStyle(MeshinowaTheme.bodyText)
                        }
                        .frame(minWidth: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(genre.title)、\(count)件")
                    }
                }
            }
        }
    }

    private func statistic<Mark: View>(_ title: String, count: Int, @ViewBuilder mark: () -> Mark) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(MeshinowaFont.number(26))
            HStack(spacing: 4) {
                mark().font(.system(size: 11)).accessibilityHidden(true)
                Text(title)
            }
            .font(MeshinowaFont.text(13, relativeTo: .caption))
            .foregroundStyle(MeshinowaTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)、\(count)件")
    }
    private func linkRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24)
            Text(title).font(MeshinowaFont.text(16))
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
        }.frame(minHeight: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
    }
}

struct ProfileIcon: View {
    /// サーバーの初期値。まだアイコンを選んでいない人には、人の形の代わりにロゴのお椀を出す。
    static let defaultSymbol = "person.fill"
    var symbol: String
    var size: CGFloat = 64
    var body: some View {
        Group {
            if symbol == Self.defaultSymbol {
                BowlMark(size: size * 0.66, holes: MeshinowaTheme.mint)
            } else {
                Image(systemName: symbol).font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(MeshinowaTheme.green)
            }
        }
        .frame(width: size, height: size)
        .background(MeshinowaTheme.mint, in: Circle()).accessibilityHidden(true)
    }
}

struct ProfileEditorView: View {
    static let icons: [(String, String)] = [
        ("person.fill", "メシノワ"), ("fork.knife", "ごはん"), ("cup.and.saucer.fill", "カフェ"),
        ("leaf.fill", "葉っぱ"), ("fish.fill", "おさかな"), ("carrot.fill", "にんじん"),
        ("birthday.cake.fill", "ケーキ"), ("sun.max.fill", "太陽")
    ]
    @EnvironmentObject private var friends: FriendStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile.name") private var localName = "ゲスト"
    @AppStorage("profile.bio") private var localBio = ""
    @AppStorage("profile.symbol") private var localSymbol = "person.fill"
    @State private var name = ""
    @State private var bio = ""
    @State private var symbol = "person.fill"
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("アイコン") {
                    HStack { Spacer(); ProfileIcon(symbol: symbol, size: 80); Spacer() }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                        ForEach(Self.icons, id: \.0) { icon in
                            Button { symbol = icon.0 } label: {
                                Group {
                                    if icon.0 == ProfileIcon.defaultSymbol { BowlMark(size: 26, holes: symbol == icon.0 ? MeshinowaTheme.mint : MeshinowaTheme.paper) }
                                    else { Image(systemName: icon.0) }
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(symbol == icon.0 ? MeshinowaTheme.mint : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel(icon.1)
                                .accessibilityAddTraits(symbol == icon.0 ? .isSelected : [])
                        }
                    }
                }
                Section("表示名（40文字まで）") { TextField("表示名", text: $name) }
                Section("自己紹介（160文字まで）") {
                    TextEditor(text: $bio).frame(minHeight: 100)
                    Text("\(bio.count) / 160文字").font(.caption).foregroundStyle(bio.count > 160 ? .red : .secondary)
                }
                Section { Text(friends.isAvailable ? "表示名・アイコン・自己紹介は、友達やID検索であなたを見つけた人に表示されます。" : "この端末に保存します。") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .font(MeshinowaFont.text(15)).scrollContentBackground(.hidden).background(MeshinowaTheme.paper)
            .navigationTitle("プロフィールを編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") { save() }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40 || bio.count > 160)
                }
            }.disabled(isSaving).interactiveDismissDisabled(isSaving)
            .onAppear {
                name = friends.me?.displayName ?? localName
                bio = friends.me?.bio ?? localBio
                symbol = friends.me?.avatarSymbol ?? localSymbol
            }
        }
    }
    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if friends.isAvailable { try await friends.updateProfile(name: clean, bio: bio, symbol: symbol) }
                localName = clean; localBio = bio; localSymbol = symbol
                dismiss()
            } catch { self.error = "保存できませんでした。通信状況を確認して、もう一度お試しください。" }
        }
    }
}

struct MyReviewsView: View {
    var onFindRestaurants: () -> Void
    @EnvironmentObject private var reviews: LocalReviewStore
    @State private var editing: LocalReview?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let error = reviews.loadError {
                    Text(error).font(MeshinowaFont.text(14))
                    Button("再読み込み") { reviews.reload() }
                } else if reviews.reviews.isEmpty {
                    Text("自分のレビューはまだありません")
                        .font(MeshinowaFont.text(20, weight: .black, relativeTo: .title2))
                    Button("マップでお店を探す", action: onFindRestaurants)
                        .buttonStyle(PaperButtonStyle())
                }
                ForEach(reviews.reviews) { review in
                    LocalReviewRow(review: review) { editing = review }
                }
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .navigationTitle("自分のレビュー")
        .reservesFloatingTabBarSpace()
        .sheet(item: $editing) { ReviewEditor(item: $0.restaurant.mapItem, existing: $0) }
    }
}

private struct LocalReviewRow: View {
    let review: LocalReview
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    FoodGenreMark(genre: review.restaurant.foodGenre, tone: .reviewed, size: 30)
                        .frame(width: 46, height: 46)
                        .background(MeshinowaTheme.photo, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Text(review.restaurant.name)
                        .font(MeshinowaFont.heading(17))
                    Spacer(minLength: 8)
                    MyRatingTag(rating: review.rating)
                }
                if !review.comment.isEmpty {
                    Text(review.comment)
                        .font(MeshinowaFont.text(14))
                        .foregroundStyle(MeshinowaTheme.bodyText)
                        .lineLimit(3)
                }
                HStack {
                    Text(review.updatedAt, style: .date)
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                    Spacer()
                    Label("編集する", systemImage: "square.and.pencil")
                        .font(MeshinowaFont.text(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.green)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MyRestaurantMapView: View {
    var onFindRestaurants: () -> Void
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @State private var selected: SavedRestaurant?

    private var restaurants: [SavedRestaurant] {
        PersonalLibrary.restaurants(saved: saved.restaurants, reviews: reviews.reviews)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("自分が保存・評価したお店 \(restaurants.count)件")
                    .font(MeshinowaFont.text(18, weight: .black, relativeTo: .headline))
                if restaurants.isEmpty {
                    Button("マップでお店を探す", action: onFindRestaurants)
                        .buttonStyle(PaperButtonStyle())
                } else {
                    SavedRestaurantMap(restaurants: restaurants,
                                       ratings: PersonalLibrary.ratings(for: restaurants, reviews: reviews.reviews)) {
                        selected = $0
                    }
                        .frame(height: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .navigationTitle("マイマップ")
        .reservesFloatingTabBarSpace()
        .sheet(item: $selected) { RestaurantInformationView(item: $0.mapItem) }
    }
}
