import SwiftUI

/// 新機能が使う部品一式。既存の型とのつなぎ込みはこのファイル（Bridges）だけで行う。
@MainActor
struct SwipeDiscoveryDependencies {
    let isDemo: Bool
    let provider: FriendReviewProvider
    let savedShops: SavedShopsBridge
    let decisionStore: SwipeDecisionStore
    let guideStore: SwipeGuideStateStore
    let location: SwipeLocationProviding
    let mapItems: SwipeMapItemRegistry
    let placePhotos: SwipePlacePhotoCache
    /// 「行きたい」の一覧。
    let wantToGo: SwipeWantToGoStore?

    /// 友達タブと同じく、サーバーから取得した友達の実データだけを使う（アプリにデモデータはない）。
    static func make(friends: FriendStore, reviews: LocalReviewStore) -> SwipeDiscoveryDependencies {
        let mapItems = SwipeMapItemRegistry()
        let provider = FriendDatasetReviewProvider(isDemo: false, mapItems: mapItems) { friends.dataset }
        let wantToGo = SwipeDiscoveryEntry.wantToGoStore
        return SwipeDiscoveryDependencies(
            isDemo: false, provider: provider,
            savedShops: WantToGoShopsBridge(wantToGo: wantToGo, reviews: reviews),
            decisionStore: SwipeDecisionStore(fileURL: SwipeDecisionStore.defaultURL()),
            guideStore: SwipeGuideStateStore(), location: SwipeLocationProvider(), mapItems: mapItems,
            placePhotos: SwipePlacePhotoCache(fetcher: SwipeGoogleMapsBridge.placePhotoFetcher(mapItems: mapItems)),
            wantToGo: wantToGo)
    }
}

/// 既存アプリの環境（EnvironmentObject）から部品を作って画面を出す。
struct SwipeDiscoveryHost: View {
    @EnvironmentObject private var friends: FriendStore
    @EnvironmentObject private var reviews: LocalReviewStore
    /// 開いている間は同じ部品を使う（友達データの更新で作り直さない）。
    @State private var dependencies: SwipeDiscoveryDependencies?

    var body: some View {
        if let dependencies {
            SwipeDiscoveryView(dependencies: dependencies)
        } else {
            SwipeTheme.background
                .ignoresSafeArea()
                .onAppear { dependencies = SwipeDiscoveryDependencies.make(friends: friends, reviews: reviews) }
        }
    }
}
