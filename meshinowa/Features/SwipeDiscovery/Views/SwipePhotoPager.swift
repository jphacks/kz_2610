import SwiftUI

/// 友達の写真を全面に敷き詰め、上端に枚数インジケーター、左下に投稿した友達を重ねる。
/// 写真の切り替えはカードの統合ジェスチャー（タップ判定）から index を変えて行い、ここではタップを受けない。
struct SwipePhotoPager: View {
    let photos: [SwipeFriendPhoto]
    let index: Int
    let category: SwipeCategory
    @ObservedObject var loader: SwipePhotoLoader

    private var current: SwipeFriendPhoto? {
        photos.isEmpty ? nil : photos[min(max(0, index), photos.count - 1)]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                ZStack {
                    SwipeTheme.heroBackground(for: category)
                    if let current, let image = loader.image(for: current.source) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } else {
                        ProgressView().tint(SwipeTheme.brand)
                    }
                }
            }
            if let current {
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                HStack(spacing: 6) {
                    SwipeFriendAvatar(name: current.review.friendName, size: 26)
                    Text(current.review.friendName)
                        .font(SwipeTheme.text(13, bold: true, relativeTo: .caption))
                        .lineLimit(1)
                    SwipeStarRating(rating: current.review.rating, size: 13)
                }
                .foregroundStyle(.white)
                .padding(12)
            }
        }
        .overlay(alignment: .top) {
            if photos.count > 1 {
                HStack(spacing: 4) {
                    ForEach(photos.indices, id: \.self) { i in
                        Capsule()
                            .fill(.white.opacity(i == index ? 0.95 : 0.4))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                // 右上の小窓と重ならないよう、右側をあける。
                .padding(.trailing, 100)
            }
        }
        .onAppear { photos.forEach { loader.load($0.source) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.map { "\($0.review.friendName)さんの写真、\(index + 1)枚目、全\(photos.count)枚" } ?? "")
    }
}

/// 友達の写真がない時に出す、店舗の写真（Google Places）。必須のクレジットを下端に添える。
struct SwipePlacePhotoView: View {
    let photo: SwipePlacePhoto

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .overlay(alignment: .bottomLeading) {
            Text(photo.shortCredit)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                .padding(8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("お店の写真、\(photo.shortCredit)")
    }
}
