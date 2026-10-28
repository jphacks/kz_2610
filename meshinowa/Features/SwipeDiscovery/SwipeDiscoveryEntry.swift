import CoreLocation
import MapKit
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
    /// 「行きたい」の一覧（いいねとは別）。既存の保存画面からもこれを使う。
    /// Cloudflare が設定されていれば同期先もつなぐ。
    @MainActor static var wantToGoStore: SwipeWantToGoStore {
        let store = SwipeWantToGoStore.shared
        if store.remote == nil { store.remote = CloudflareWantToGoRemote.makeDefault() }
        return store
    }

    /// 保存画面を開いた時に呼ぶ。レビューを書いた（行った）お店を外し、サーバーと同期する。
    @MainActor static func refreshWantToGo(reviewedIDs: Set<String>) async {
        let store = wantToGoStore
        store.removeVisited { reviewedIDs.contains($0) }
        await store.sync()
    }

    /// 「行きたい」のお店を、既存の保存画面で使う形にする。
    @MainActor static func wantToGoRestaurants() -> [SavedRestaurant] {
        wantToGoStore.entries.map(\.savedRestaurant)
    }

    /// 保存画面の「行きたい」から外す。
    @MainActor static func removeFromWantToGo(shopID: String) throws {
        try wantToGoStore.remove(shopID: shopID)
    }

    /// 地図のお店カードに置く小さな「行きたい」ボタン。
    @ViewBuilder
    static func wantToGoButton(item: MKMapItem, compact: Bool = false) -> some View {
        if SwipeDiscoveryFeature.isEnabled {
            SwipeWantToGoButton(item: item, compact: compact)
        }
    }

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
                        .overlay(Image(systemName: "flag.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                        .rotationEffect(.degrees(8))
                        .offset(x: 6)
                }
                .frame(width: 56, height: 52)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("お店スワイプ")
                        .font(SwipeTheme.heading(17))
                        .foregroundStyle(SwipeTheme.ink)
                    Text("友達が行った近くのお店を、右で行きたい・左でイマイチ")
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

/// 「行きたい」の切り替えボタン（地図のお店カード用）。お店スワイプの右スワイプと同じ一覧に入る。
struct SwipeWantToGoButton: View {
    let item: MKMapItem
    /// true なら文字なしの旗だけ。お店カードで、いいねのハートの隣に並べる。
    var compact = false
    @ObservedObject private var store = SwipeDiscoveryEntry.wantToGoStore
    @State private var errorMessage: String?

    var body: some View {
        let isOn = store.contains(SwipeWantToGoEntry.shopID(for: item))
        Button { toggle(isOn: isOn) } label: {
            if compact {
                Image(systemName: isOn ? "flag.fill" : "flag")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isOn ? SwipeTheme.brand : MeshinowaTheme.secondaryText)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            } else {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "flag.fill" : "flag")
                    .font(.system(size: 11, weight: .bold))
                Text("行きたい")
                    .font(SwipeTheme.text(12, bold: true, relativeTo: .caption))
            }
            .foregroundStyle(isOn ? Color.white : SwipeTheme.tagText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isOn ? SwipeTheme.brand : SwipeTheme.tagBackground, in: Capsule())
            .frame(minHeight: 36)
            .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel("行きたい")
        .accessibilityValue(isOn ? "登録済み" : "未登録")
        .accessibilityHint(isOn ? "行きたいから外します" : "行きたいに追加します")
        .alert("行きたいを変更できませんでした", isPresented: Binding(get: { errorMessage != nil },
                                                          set: { if !$0 { errorMessage = nil } })) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func toggle(isOn: Bool) {
        do {
            if isOn {
                try store.remove(shopID: SwipeWantToGoEntry.shopID(for: item))
            } else {
                try store.add(entry: SwipeWantToGoEntry(item: item))
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "もう一度お試しください。"
        }
    }
}
