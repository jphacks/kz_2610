import SwiftUI
import MapKit

struct RestaurantShareCardEditor: View {
    let item: MKMapItem
    @EnvironmentObject private var reviews: LocalReviewStore
    @EnvironmentObject private var friends: FriendStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile.name") private var localName = ""
    @State private var includesName = false
    @State private var includesRating = true
    @State private var includesComment = true
    @State private var includesPhoto = false
    @State private var share: CardSharePayload?
    @State private var renderFailed = false

    private var review: LocalReview? { reviews.review(for: item) }
    private var name: String { friends.me?.displayName ?? (localName.isEmpty ? "あなた" : localName) }
    private var photo: UIImage? {
        guard includesPhoto, let filename = review?.photoFileNames.first,
              let url = reviews.photoURL(filename) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    private var card: RestaurantShareCard {
        RestaurantShareCard(item: item, name: includesName ? name : nil,
                            rating: includesRating ? review?.rating : nil,
                            comment: includesComment ? review?.comment : nil, photo: photo)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("おすすめを、1枚に。")
                        .font(MeshinowaFont.heading(22))
                    card
                        .scaleEffect(0.8, anchor: .top)
                        .frame(width: 288, height: 360)
                        .accessibilityLabel("共有するカードのプレビュー")
                    VStack(spacing: 14) {
                        Toggle("自分の名前", isOn: $includesName)
                        if review != nil { Toggle("自分の評価", isOn: $includesRating) }
                        if let comment = review?.comment, !comment.isEmpty {
                            Toggle("ひとこと", isOn: $includesComment)
                        }
                        if review?.photoFileNames.isEmpty == false {
                            Toggle("自分の写真（最初の1枚）", isOn: $includesPhoto)
                        }
                    }
                    .padding(18)
                    .background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MeshinowaTheme.hairline))
                    Text("友達の名前・評価・コメントは載りません。共有する前に、画像の内容をご確認ください。")
                        .font(MeshinowaFont.text(13))
                        .foregroundStyle(MeshinowaTheme.bodyText)
                    Button(action: makeShare) {
                        Label("カードを共有する", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PaperButtonStyle())
                    .accessibilityIdentifier("shareCard.share")
                }
                .padding(20)
            }
            .font(MeshinowaFont.text(15))
            .background(MeshinowaTheme.ground)
            .foregroundStyle(MeshinowaTheme.ink)
            .navigationTitle("カードにして共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .sheet(item: $share) { payload in ActivityShareSheet(items: [payload.image, payload.message]) }
            .alert("カードを作成できませんでした", isPresented: $renderFailed) {
                Button("閉じる", role: .cancel) {}
            } message: { Text("もう一度お試しください。") }
        }
        .tint(MeshinowaTheme.green)
    }

    @MainActor private func makeShare() {
        let renderer = ImageRenderer(content: card.environment(\.dynamicTypeSize, .medium))
        renderer.scale = 3
        guard let image = renderer.uiImage else { renderFailed = true; return }
        share = CardSharePayload(image: image, message: RestaurantSharing.message(for: item))
    }
}

private struct CardSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let message: String
}

/// 外部へ出す画像。Googleの店舗写真や友達の記録を受け取らない。
struct RestaurantShareCard: View {
    let item: MKMapItem
    let name: String?
    let rating: Double?
    let comment: String?
    let photo: UIImage?

    private var genre: FoodGenre { FoodGenre.infer(name: item.name, category: item.pointOfInterestCategory?.rawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        MeshinowaTheme.photo.overlay { FoodGenreMark(genre: genre, size: 86) }
                    }
                }
                .frame(width: 328, height: 172).clipped()
                GenreRibbon(genre: genre).padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name ?? "飲食店").font(MeshinowaFont.heading(22)).lineLimit(2)
                    Text([genre.title, RestaurantSharing.area(for: item)].filter { !$0.isEmpty }.joined(separator: "・"))
                        .font(MeshinowaFont.text(12)).foregroundStyle(MeshinowaTheme.bodyText).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let rating {
                    VStack(spacing: 0) {
                        Text(rating, format: .number.precision(.fractionLength(1))).font(MeshinowaFont.number(24))
                        Text("自分の評価").font(MeshinowaFont.text(9, weight: .bold))
                    }
                    .foregroundStyle(MeshinowaTheme.mustardInk)
                    .frame(width: 60, height: 60)
                    .background(MeshinowaTheme.mustardSoft, in: Circle())
                    .overlay(Circle().strokeBorder(MeshinowaTheme.accent, lineWidth: 2))
                    .rotationEffect(.degrees(-6))
                }
            }
            if let comment, !comment.isEmpty {
                Text(comment).font(MeshinowaFont.text(14)).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                BowlMark(size: 26, holes: MeshinowaTheme.ground)
                VStack(alignment: .leading, spacing: 1) {
                    Text("メシノワ").font(MeshinowaFont.heading(14))
                    Text("友達のおすすめを地図で").font(MeshinowaFont.text(10))
                }
                Spacer(minLength: 0)
                if let name { Text("\(name)のおすすめ").font(MeshinowaFont.text(11)).lineLimit(1) }
            }
        }
        .padding(16).frame(width: 360, height: 450)
        .foregroundStyle(MeshinowaTheme.ink)
        .background(MeshinowaTheme.ground)
        .environment(\.dynamicTypeSize, .medium)
        .environment(\.colorScheme, .light)
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
