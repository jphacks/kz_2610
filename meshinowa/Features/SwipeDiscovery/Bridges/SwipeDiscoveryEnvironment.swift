import CoreLocation
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
    static func make(friends: FriendStore, reviews: LocalReviewStore, location: LocationStore) -> SwipeDiscoveryDependencies {
        removeLegacyDemoData()
        let mapItems = SwipeMapItemRegistry()
        let provider = FriendDatasetReviewProvider(isDemo: false, mapItems: mapItems) { friends.dataset }
        let wantToGo = SwipeDiscoveryEntry.wantToGoStore
        return SwipeDiscoveryDependencies(
            isDemo: false, provider: provider,
            savedShops: WantToGoShopsBridge(wantToGo: wantToGo, reviews: reviews),
            decisionStore: SwipeDecisionStore(fileURL: SwipeDecisionStore.defaultURL()),
            guideStore: SwipeGuideStateStore(), location: AppLocationBridge(store: location), mapItems: mapItems,
            placePhotos: SwipePlacePhotoCache(fetcher: SwipeGoogleMapsBridge.placePhotoFetcher(mapItems: mapItems)),
            wantToGo: wantToGo)
    }
}

extension SwipeDiscoveryDependencies {
    /// 以前のデモ（架空の店）の判断記録と保存先を消す。アプリからデモがなくなったので使わない。
    static func removeLegacyDemoData(defaults: UserDefaults = .standard) {
        try? FileManager.default.removeItem(at: SwipeDecisionStore.defaultURL(fileName: "swipe_decisions_demo.json"))
        defaults.removeObject(forKey: "swipeDiscovery.demoWantToGo")
    }
}

/// 既存アプリの環境（EnvironmentObject）から部品を作って画面を出す。
struct SwipeDiscoveryHost: View {
    @EnvironmentObject private var friends: FriendStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @EnvironmentObject private var location: LocationStore
    /// 開いている間は同じ部品を使う（友達データの更新で作り直さない）。
    @State private var dependencies: SwipeDiscoveryDependencies?

    var body: some View {
        if let dependencies {
            SwipeDiscoveryView(dependencies: dependencies)
        } else {
            SwipeTheme.background
                .ignoresSafeArea()
                .onAppear { dependencies = SwipeDiscoveryDependencies.make(friends: friends, reviews: reviews, location: location) }
        }
    }
}

/// アプリの位置情報（LocationStore）を使う。地図と同じく、押した時だけ許可を求め、常時の追跡はしない。
@MainActor
final class AppLocationBridge: SwipeLocationProviding {
    private let store: LocationStore

    init(store: LocationStore) {
        self.store = store
    }

    func currentLocation() async -> CLLocationCoordinate2D? {
        store.location?.coordinate
    }

    func requestCurrentLocation() async -> Result<CLLocationCoordinate2D, SwipeLocationError> {
        let before = store.location?.timestamp
        store.request()
        // 許可の確認画面に答えてもらう時間も含めて待つ。
        for _ in 0..<300 where store.isRequesting {
            try? await Task.sleep(for: .milliseconds(200))
        }
        if let location = store.location, before == nil || location.timestamp > before! {
            return .success(location.coordinate)
        }
        return .failure(SwipeLocationError(message: store.error ?? "現在地を取得できませんでした。もう一度お試しください。"))
    }
}
