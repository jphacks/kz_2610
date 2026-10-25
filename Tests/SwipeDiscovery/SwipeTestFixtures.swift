import CoreLocation
import Foundation
@testable import meshinowa

/// お店スワイプのテスト用データ。すべて架空。
enum SwipeFixtures {
    static let tokyo = (latitude: 35.6812, longitude: 139.7671)

    static func review(_ id: String, friend: String = "f1", rating: Double = 4,
                       updatedAt: TimeInterval = 0, comment: String? = nil, dish: String? = nil,
                       photos: [SwipePhotoSource] = []) -> SwipeFriendReview {
        SwipeFriendReview(id: id, friendID: friend, friendName: "友達\(friend)", rating: rating, comment: comment,
                          recommendedDish: dish, updatedAt: Date(timeIntervalSince1970: updatedAt), photos: photos)
    }

    /// 東京駅から北へ `metersNorth` 離れた店。
    static func candidate(_ id: String, metersNorth: Double = 100, genre: String? = "ラーメン",
                          reviews: [SwipeFriendReview]? = nil) -> SwipeCandidate {
        SwipeCandidate(id: id, name: "架空の店\(id)", genre: genre, address: "架空の住所",
                       latitude: tokyo.latitude + metersNorth / 111_000, longitude: tokyo.longitude,
                       reviews: reviews ?? [review("r-\(id)")])
    }

    static func decision(_ id: String, kind: SwipeDecisionKind, at time: TimeInterval) -> SwipeDecision {
        SwipeDecision(candidate: candidate(id), kind: kind, decidedAt: Date(timeIntervalSince1970: time))
    }

    static func temporaryURL(_ name: String = "swipe_decisions.json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SwipeDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}

/// 取得元のモック。
struct MockFriendReviewProvider: FriendReviewProvider {
    var isDemo = false
    var result: Result<[SwipeCandidate], Error>

    func candidates(near center: CLLocationCoordinate2D, radius: CLLocationDistance,
                    lens: SwipeFriendLens) async throws -> [SwipeCandidate] {
        try result.get()
    }

    func friends() async -> [SwipeFriendProfile] { [] }
}

/// 位置は常に既定エリア。
struct MockLocationProvider: SwipeLocationProviding {
    func currentLocation() async -> CLLocationCoordinate2D? { nil }
    func requestCurrentLocation() async -> Result<CLLocationCoordinate2D, SwipeLocationError> {
        .failure(SwipeLocationError(message: "位置情報を使えません（テスト）"))
    }
}

/// 「行きたい」のモック。
@MainActor
final class MockSavedShopsBridge: SavedShopsBridge {
    struct Failure: LocalizedError { var errorDescription: String? { "保存に失敗しました（テスト）" } }

    var wantToGo: Set<String> = []
    var visited: Set<String> = []
    var failsToAdd = false
    let wantToGoTitle = "行きたい"
    let savedNotice = "行きたいに保存しました"

    func prepare() async {}
    func isExcluded(shopID: String) -> Bool { wantToGo.contains(shopID) || visited.contains(shopID) }
    func addToWantToGo(_ candidate: SwipeCandidate) throws {
        if failsToAdd { throw Failure() }
        wantToGo.insert(candidate.id)
    }
    func removeFromWantToGo(shopID: String) throws { wantToGo.remove(shopID) }
}

/// サーバーのモック。
final class MockWantToGoRemote: SwipeWantToGoRemote {
    var items: [String: SwipeWantToGoRemoteItem] = [:]
    var fails = false
    private(set) var removedKeys: [String] = []

    func add(_ entry: SwipeWantToGoEntry) async throws -> String {
        if fails { throw URLError(.notConnectedToInternet) }
        let id = "remote-\(entry.id)"
        items[entry.id] = SwipeWantToGoRemoteItem(restaurantID: id, externalKey: entry.id, name: entry.name,
                                                  category: nil, address: entry.address, latitude: entry.latitude,
                                                  longitude: entry.longitude, addedAt: entry.addedAt)
        return id
    }

    func remove(_ entry: SwipeWantToGoEntry) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        removedKeys.append(entry.id)
        items[entry.id] = nil
    }

    func list() async throws -> [SwipeWantToGoRemoteItem] {
        if fails { throw URLError(.notConnectedToInternet) }
        return Array(items.values)
    }
}

@MainActor
extension SwipeDiscoveryDependencies {
    static func test(provider: FriendReviewProvider, bridge: SavedShopsBridge, storeURL: URL,
                     defaults: UserDefaults) -> SwipeDiscoveryDependencies {
        SwipeDiscoveryDependencies(
            isDemo: false, provider: provider, savedShops: bridge,
            decisionStore: SwipeDecisionStore(fileURL: storeURL),
            guideStore: SwipeGuideStateStore(defaults: defaults), location: MockLocationProvider(),
            mapItems: SwipeMapItemRegistry(), placePhotos: SwipePlacePhotoCache(fetcher: nil), wantToGo: nil)
    }
}
