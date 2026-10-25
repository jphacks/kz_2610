import SwiftUI

/// BeReal の小窓のように、カード右上へ重ねる小さな地図と距離（F-07）。
/// タップはカードの統合ジェスチャーで受けるため、ここでは受けない。
struct SwipeLocationInset: View {
    static let mapSize: CGFloat = 88

    let candidate: SwipeCandidate
    let distanceMeters: Double
    /// 最前面のカードだけ実際の地図を出す（地図を何枚も同時に動かさない）。
    var isLive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if isLive {
                    SwipeShopMapView(candidate: candidate)
                } else {
                    ZStack {
                        SwipeTheme.mapPlaceholder
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(SwipeTheme.brand)
                    }
                }
            }
            .frame(width: Self.mapSize, height: Self.mapSize)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)

            Text(SwipeDistanceFormatter.label(meters: distanceMeters))
                .font(SwipeTheme.text(11, bold: true, relativeTo: .caption2))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(SwipeTheme.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(SwipeTheme.card.opacity(0.92), in: Capsule())
                .frame(maxWidth: Self.mapSize + 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SwipeDistanceFormatter.accessibilityLabel(meters: distanceMeters))
        .accessibilityHint("地図を大きく開きます")
    }
}

/// 小窓をタップした時の大きな地図。
struct SwipeLargeMapSheet: View {
    let candidate: SwipeCandidate
    let distanceMeters: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SwipeShopMapView(candidate: candidate, interactive: true, spanMeters: 1200)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(candidate.name)
                            .font(SwipeTheme.heading(18))
                        Text("\(SwipeDistanceFormatter.label(meters: distanceMeters))（直線距離の目安）")
                            .font(SwipeTheme.text(13))
                            .foregroundStyle(SwipeTheme.bodyText)
                    }
                    .foregroundStyle(SwipeTheme.ink)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SwipeTheme.card)
                }
                .navigationTitle("お店の場所")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
    }
}
