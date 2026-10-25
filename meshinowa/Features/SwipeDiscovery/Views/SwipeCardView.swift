import SwiftUI

/// 1枚のカード。上部は友達の写真（なければ店舗の写真、それもなければ星評価ビュー）、右上に位置の小窓、下部に情報エリア。
/// タップとドラッグは SwipeCardStackView が DragGesture(minimumDistance: 0) 1つで判定する。TapGesture は重ねない。
struct SwipeCardView: View {
    static let coordinateSpace = "SwipeCardView.card"
    static let cornerRadius: CGFloat = 20

    let candidate: SwipeCandidate
    let distanceMeters: Double
    let isTop: Bool
    var photoIndex = 0
    var dragX: CGFloat = 0
    @ObservedObject var photoLoader: SwipePhotoLoader
    @ObservedObject var placePhotos: SwipePlacePhotoCache
    /// タップ判定に使う領域（最前面のカードだけ知らせる）。
    var onRegionsChange: (SwipeCardRegions) -> Void = { _ in }

    @State private var frames: [String: CGRect] = [:]

    private var usablePhotos: [SwipeFriendPhoto] { photoLoader.usablePhotos(candidate.photos) }

    private var regions: SwipeCardRegions {
        SwipeCardRegions(size: frames["card"]?.size ?? .zero,
                         locationInset: frames["inset"] ?? .null,
                         infoArea: frames["info"] ?? .null,
                         showsPhotos: !usablePhotos.isEmpty)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                media
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        SwipeLocationInset(candidate: candidate, distanceMeters: distanceMeters, isLive: isTop)
                            .reportFrame("inset")
                            .padding(12)
                    }
                info
                    .reportFrame("info")
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .reportFrame("card")
            .background(SwipeTheme.card)
            .overlay { overlay(width: proxy.size.width) }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(SwipeTheme.hairline, lineWidth: 1))
            .coordinateSpace(name: Self.coordinateSpace)
            .onPreferenceChange(SwipeCardFrameKey.self) { frames = $0 }
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .onAppear {
            candidate.photos.forEach { photoLoader.load($0.source) }
            if candidate.photos.isEmpty { placePhotos.load(candidate) }
        }
        .onChange(of: regions) { _, regions in
            if isTop { onRegionsChange(regions) }
        }
        .onChange(of: isTop) { _, isTop in
            if isTop { onRegionsChange(regions) }
        }
        .onChange(of: usablePhotos.isEmpty) { _, isEmpty in
            // 友達の写真が全部読み込めなかった時は、店舗の写真→星評価ビューの順に切り替える。
            if isEmpty { placePhotos.load(candidate) }
        }
    }

    // MARK: - 上部

    @ViewBuilder private var media: some View {
        let photos = usablePhotos
        if !photos.isEmpty {
            SwipePhotoPager(photos: photos, index: photoIndex % photos.count, category: candidate.category,
                            loader: photoLoader)
        } else {
            switch placePhotos.state(for: candidate) {
            case .loaded(let photo):
                SwipePlacePhotoView(photo: photo)
            case .loading:
                ZStack {
                    SwipeTheme.heroBackground(for: candidate.category)
                    ProgressView().tint(SwipeTheme.brand)
                }
            case .unavailable:
                SwipeRatingHero(candidate: candidate)
            }
        }
    }

    // MARK: - 情報エリア

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.name)
                .font(SwipeTheme.heading(22, relativeTo: .title2))
                .foregroundStyle(SwipeTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            HStack(spacing: 6) {
                SwipeStarRating(rating: candidate.averageRating, size: 15)
                Text("・友達\(candidate.reviews.count)人")
                    .font(SwipeTheme.text(13, relativeTo: .caption))
                    .foregroundStyle(SwipeTheme.secondaryText)
                Spacer(minLength: 0)
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(SwipeTheme.secondaryText)
                    .accessibilityHidden(true)
            }
            if let comment = candidate.latestComment {
                Text("「\(comment)」")
                    .font(SwipeTheme.text(13, relativeTo: .caption))
                    .foregroundStyle(SwipeTheme.bodyText)
                    .lineLimit(1)
            }
            SwipeTagRow(candidate: candidate)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SwipeTheme.card)
    }

    // MARK: - オーバーレイ

    @ViewBuilder private func overlay(width: CGFloat) -> some View {
        if isTop, dragX != 0 {
            SwipeOverlayView(kind: dragX > 0 ? .interested : .notInterested,
                             opacity: SwipeGestureEvaluator.overlayOpacity(translationX: dragX, cardWidth: width))
        }
    }
}

struct SwipeCardFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// カードの座標系での自分の位置を知らせる（タップの振り分け用）。
    func reportFrame(_ name: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: SwipeCardFrameKey.self,
                                   value: [name: proxy.frame(in: .named(SwipeCardView.coordinateSpace))])
        })
    }
}
