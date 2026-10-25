import CoreLocation
import SwiftUI

/// 機能フラグと既定値。false にすると入口ごと消え、既存機能は導入前と同じように動く。
enum SwipeDiscoveryFeature {
    static let isEnabled = true
    /// 位置情報の許可がない時の既定エリア（既存の地図・友達デモと同じ東京駅周辺）。
    static let defaultCenter = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
    static let defaultAreaName = "東京駅周辺"
}

/// 外部に公開する唯一の入口。既存画面にはこの1行だけを足す。
///
/// ```swift
/// // 友達タブのフィードの先頭に1行追加
/// SwipeDiscoveryEntry.feedBanner()
/// ```
enum SwipeDiscoveryEntry {
    @ViewBuilder
    static func feedBanner() -> some View {
        if SwipeDiscoveryFeature.isEnabled {
            SwipeDiscoveryEntryBanner()
        }
    }
}

/// 友達のフィードの先頭に出す入口。タブバーに隠れないよう全画面で開く。
struct SwipeDiscoveryEntryBanner: View {
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SwipeTheme.card)
                        .frame(width: 34, height: 44)
                        .rotationEffect(.degrees(-10))
                        .offset(x: -6)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SwipeTheme.interested)
                        .frame(width: 34, height: 44)
                        .overlay(Image(systemName: "heart.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                        .rotationEffect(.degrees(8))
                        .offset(x: 6)
                }
                .frame(width: 56, height: 52)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("お店スワイプ")
                        .font(SwipeTheme.heading(17))
                        .foregroundStyle(SwipeTheme.ink)
                    Text("友達が行った近くのお店を、右で気になる・左でイマイチ")
                        .font(SwipeTheme.text(13, relativeTo: .caption))
                        .foregroundStyle(SwipeTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SwipeTheme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SwipeTheme.tagBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityHint("お店スワイプを開きます")
        .fullScreenCover(isPresented: $isPresented) {
            SwipeDiscoveryHost()
        }
    }
}
