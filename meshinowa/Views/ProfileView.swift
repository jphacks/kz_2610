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
                HStack(spacing: 12) {
                    ProfileIcon(symbol: friends.me?.avatarSymbol ?? localSymbol, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(friends.me?.displayName ?? localName).font(MeshinowaFont.heading(22))
                        Text("この端末のプロフィール")
                            .font(MeshinowaFont.text(13)).foregroundStyle(MeshinowaTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Button { editsProfile = true } label: {
                        Label("編集", systemImage: "pencil")
                            .font(MeshinowaFont.text(13, weight: .bold))
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .overlay(Capsule().strokeBorder(MeshinowaTheme.outline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("プロフィールを編集")
                    .disabled(friends.isAvailable && friends.me == nil)
                }
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
                }.padding(.vertical, 14).background(MeshinowaTheme.field, in: RoundedRectangle(cornerRadius: 16))

                if friends.isAvailable && !reviews.pending.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("友達への共有待ち \(reviews.pending.count)件", systemImage: "arrow.triangle.2.circlepath")
                        if let error = friends.syncError { Text(error).font(MeshinowaFont.text(13)) }
                        Button("今すぐ再試行") { Task { await friends.flushReviews() } }
                    }.font(MeshinowaFont.text(14)).padding(16).paperCard()
                }
                genreShelf

                if let error = reviews.loadError {
                    Text(error).font(MeshinowaFont.text(14))
                    Button("レビューを再読み込み") { reviews.reload() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("最近のレビュー").font(MeshinowaFont.heading(20, relativeTo: .title2))
                        Spacer()
                        NavigationLink { MyReviewsView(onFindRestaurants: onFindRestaurants) } label: {
                            Text("すべて見る").font(MeshinowaFont.text(13, weight: .bold))
                                .foregroundStyle(MeshinowaTheme.green)
                        }
                    }
                    if reviews.reviews.isEmpty && reviews.loadError == nil {
                        Text("まだレビューがありません。お店の詳細から星だけでも記録できます。")
                            .font(MeshinowaFont.text(14)).padding(.top, 6)
                    }
                    ForEach(Array(reviews.reviews.prefix(3))) { review in
                        LocalReviewRow(review: review, compact: true) { editing = review }
                    }
                }
                NavigationLink { MyRestaurantMapView(onFindRestaurants: onFindRestaurants) } label: {
                    linkRow("マイマップ", symbol: "map")
                }
                .buttonStyle(.plain)
            }.padding(20)
        }
        .refreshable { await friends.retryConnection() }
        .background(MeshinowaTheme.paper).foregroundStyle(MeshinowaTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { ReviewEditor(item: $0.restaurant.mapItem, existing: $0) }
        .sheet(isPresented: $editsProfile) { ProfileEditorView() }
    }

    private var divider: some View {
        Rectangle().fill(MeshinowaTheme.hairline).frame(width: 1, height: 36)
    }

    /// レビューしたお店を、ジャンルの器の形で数える。まだ行っていないジャンルは薄く出し、集める楽しさを作る。
    private var genreShelf: some View {
        let counts = Dictionary(grouping: reviews.reviews, by: { $0.restaurant.foodGenre }).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("よく行くジャンル").font(MeshinowaFont.heading(20, relativeTo: .title2))
                Spacer()
                let genres = FoodGenre.allCases.filter { $0 != .other }
                Text("\(genres.filter { (counts[$0] ?? 0) > 0 }.count) / \(genres.count) ジャンル")
                    .font(MeshinowaFont.text(13)).foregroundStyle(MeshinowaTheme.secondaryText)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 12) {
                ForEach(FoodGenre.allCases.filter { $0 != .other }) { genre in
                    let count = counts[genre] ?? 0
                    VStack(spacing: 5) {
                        FoodGenreMark(genre: genre, size: 36).opacity(count > 0 ? 1 : 0.4)
                        Text(count > 0 ? "\(genre.title) \(count)" : genre.title)
                            .font(MeshinowaFont.text(11, weight: count > 0 ? .bold : .medium, relativeTo: .caption2))
                            .foregroundStyle(count > 0 ? MeshinowaTheme.ink : MeshinowaTheme.secondaryText)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(genre.title)、\(count)件")
                }
            }
        }
    }

    private func statistic<Mark: View>(_ title: String, count: Int, @ViewBuilder mark: () -> Mark) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(MeshinowaFont.number(24))
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
    var compact = false
    var onEdit: () -> Void
    @EnvironmentObject private var reviews: LocalReviewStore

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    Group {
                        if let name = review.photoFileNames.first, let url = reviews.photoURL(name),
                           let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            FoodGenreMark(genre: review.restaurant.foodGenre, size: 30)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).background(MeshinowaTheme.photo)
                        }
                    }
                    .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(review.restaurant.name).font(MeshinowaFont.heading(16)).lineLimit(2)
                        if compact {
                            Text(review.visitedOn ?? review.updatedAt, style: .date)
                                .font(MeshinowaFont.text(12, relativeTo: .caption))
                                .foregroundStyle(MeshinowaTheme.secondaryText)
                        }
                    }
                    Spacer(minLength: 8)
                    MyRatingTag(rating: review.rating)
                }
                if !compact && !review.comment.isEmpty {
                    Text(review.comment)
                        .font(MeshinowaFont.text(14))
                        .foregroundStyle(MeshinowaTheme.bodyText)
                        .lineLimit(3)
                }
                if !compact { HStack {
                    Text(review.updatedAt, style: .date)
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                    Spacer()
                    Label("編集する", systemImage: "square.and.pencil")
                        .font(MeshinowaFont.text(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.green)
                } }
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
