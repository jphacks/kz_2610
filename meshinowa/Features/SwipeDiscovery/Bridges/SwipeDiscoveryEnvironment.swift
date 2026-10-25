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
    /// 「行きたい」の一覧（デモでは nil）。
    let wantToGo: SwipeWantToGoStore?

    func directionsURL(for candidate: SwipeCandidate) -> URL? {
        SwipeGoogleMapsBridge.walkingDirectionsURL(for: candidate, mapItems: mapItems)
    }

    /// サーバー接続時は友達の実データ、未接続は Friend Lens のデモ（友達タブと同じ切り替え）。
    static func make(friends: FriendStore, reviews: LocalReviewStore) -> SwipeDiscoveryDependencies {
        let isDemo = !friends.isAvailable
        let mapItems = SwipeMapItemRegistry()
        let provider = FriendDatasetReviewProvider(isDemo: isDemo, mapItems: mapItems) {
            isDemo ? DemoRecommendations.dataset : friends.dataset
        }
        let wantToGo: SwipeWantToGoStore? = isDemo ? nil : SwipeWantToGoStore.shared
        if let wantToGo, wantToGo.remote == nil { wantToGo.remote = CloudflareWantToGoRemote.makeDefault() }
        let savedShops: SavedShopsBridge = wantToGo.map { WantToGoShopsBridge(wantToGo: $0, reviews: reviews) }
            ?? DemoSavedShopsBridge()
        // デモ（架空の店）と実データの判断記録は混ぜない。
        let store = SwipeDecisionStore(fileURL: SwipeDecisionStore.defaultURL(
            fileName: isDemo ? "swipe_decisions_demo.json" : "swipe_decisions.json"))
        // 架空の店で実在店舗の写真を探さない。
        let photos = SwipePlacePhotoCache(fetcher: isDemo ? nil : SwipeGoogleMapsBridge.placePhotoFetcher(mapItems: mapItems))
        return SwipeDiscoveryDependencies(
            isDemo: isDemo, provider: provider, savedShops: savedShops, decisionStore: store,
            guideStore: SwipeGuideStateStore(), location: SwipeLocationProvider(), mapItems: mapItems,
            placePhotos: photos, wantToGo: wantToGo)
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
