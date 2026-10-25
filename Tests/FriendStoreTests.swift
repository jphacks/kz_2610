import MapKit
import XCTest
@testable import meshinowa

@MainActor
final class FriendStoreTests: XCTestCase {
    private let credentials = GuestCredentialStore(service: "jp.meshinowa.app.tests.\(UUID().uuidString)")
    private let token = String(repeating: "c", count: 64)

    override func tearDown() {
        credentials.delete()
        BackendURLProtocol.handler = nil
        super.tearDown()
    }

    private func store() -> FriendStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendURLProtocol.self]
        let backend = CloudflareBackend(configuration: BackendConfiguration(url: URL(string: "https://api.example.test")!),
                                        session: URLSession(configuration: config))
        return FriendStore(backend: backend, credentials: credentials)
    }

    func testWithoutBackendStaysUnavailable() async {
        let store = FriendStore(backend: nil, credentials: credentials)
        await store.start(sharing: [])
        XCTAssertEqual(store.status, .unavailable)
        XCTAssertNil(credentials.load())
    }

    func testStartCreatesGuestOnceAndBuildsFriendDataset() async throws {
        var guestCalls = 0
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)))
        item.name = "架空の食堂"
        let key = SavedRestaurant.identifier(for: item)
        BackendURLProtocol.handler = { [token] request in
            let path = request.url?.path ?? ""
            if path == "/v1/auth/guest" {
                guestCalls += 1
                return (201, Data("{\"access_token\":\"\(token)\",\"expires_at\":1,\"user_id\":\"00000000-0000-0000-0000-000000000001\"}".utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            switch path {
            case "/v1/me":
                return (200, Data("{\"id\":\"me\",\"display_name\":\"ゲスト\",\"handle\":\"abc2345\"}".utf8))
            case "/v1/friends":
                return (200, Data("[{\"id\":\"f1\",\"display_name\":\"はなこ\",\"handle\":\"hanako1\",\"is_favorite\":1}]".utf8))
            case "/v1/requests":
                return (200, Data("[{\"id\":\"r1\",\"from_id\":\"f2\",\"to_id\":\"me\",\"status\":\"pending\",\"from_name\":\"たろう\",\"from_handle\":\"taro123\",\"to_name\":\"ゲスト\",\"to_handle\":\"abc2345\"}]".utf8))
            case "/v1/friend-reviews":
                let review = "{\"id\":\"v1\",\"user_id\":\"f1\",\"display_name\":\"はなこ\",\"rating\":4.5,\"comment\":\"架空のひとこと\",\"dish\":\"\",\"updated_at\":\"2026-10-25T01:02:03.456Z\",\"restaurant_id\":\"s1\",\"external_key\":\"\(key)\",\"name\":\"架空の食堂\",\"category\":\"MKPOICategoryCafe\",\"address\":\"東京都\",\"latitude\":35.68,\"longitude\":139.76}"
                return (200, Data("[\(review)]".utf8))
            default:
                XCTFail("Unexpected path \(path)")
                return (404, Data("{}".utf8))
            }
        }
        let store = store()
        await store.start(sharing: [])
        await store.refresh()

        XCTAssertEqual(guestCalls, 1)
        XCTAssertEqual(credentials.load(), token)
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.me?.handle, "abc2345")
        XCTAssertEqual(store.incomingRequests.map(\.fromName), ["たろう"])
        XCTAssertTrue(store.outgoingRequests.isEmpty)

        let dataset = store.dataset
        XCTAssertFalse(dataset.isDemo)
        XCTAssertEqual(dataset.favoriteFriendIDs, ["f1"])
        XCTAssertEqual(dataset.restaurants.map(\.genre), ["カフェ"])
        XCTAssertEqual(dataset.friendName("f1"), "はなこ")
        let summary = store.summary(for: item)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.average, 4.5)
        XCTAssertEqual(store.ratingText(for: item), "友達1人の評価 4.5")
    }
}
