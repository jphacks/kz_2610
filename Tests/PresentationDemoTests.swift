import MapKit
import XCTest
@testable import meshinowa

@MainActor
final class PresentationDemoTests: XCTestCase {
    func testNormalBuildDoesNotExposePresentationData() {
#if !PRESENTATION_DEMO
        XCTAssertFalse(PresentationDemo.isEnabled)
        XCTAssertNil(PresentationDemo.dataset)
        XCTAssertTrue(PresentationDemo.restaurants.isEmpty)
#endif
    }

#if PRESENTATION_DEMO
    func testCatalogUsesStableStoreKeysAndValidLocationsAroundKIT() throws {
        XCTAssertTrue(PresentationDemo.isEnabled)
        let data = try XCTUnwrap(PresentationDemo.dataset)
        XCTAssertEqual(data.friends.count, 6)
        XCTAssertEqual(PresentationDemo.restaurants.count, 6)
        XCTAssertEqual(data.reviews.count, 12)
        XCTAssertEqual(data.ratedRestaurants.count, 5)
        XCTAssertEqual(Set(PresentationDemo.restaurants.map(\.id)).count, 6)
        let campus = CLLocation(latitude: 36.5299588, longitude: 136.6292489)
        for shop in PresentationDemo.restaurants {
            XCTAssertEqual(shop.id, SavedRestaurant.identifier(for: shop.mapItem))
            XCTAssertLessThan(CLLocation(latitude: shop.coordinate.latitude, longitude: shop.coordinate.longitude).distance(from: campus), 2000)
            XCTAssertEqual(SavedRestaurant(item: shop.mapItem).mapItem.foodGenre, shop.foodGenreHint)
        }
        for review in data.reviews {
            XCTAssertTrue(data.friends.contains { $0.id == review.friendID })
            XCTAssertTrue(data.restaurants.contains { $0.id == review.restaurantID })
            XCTAssertTrue((1...5).contains(review.rating))
            XCTAssertEqual(review.rating * 2, floor(review.rating * 2))
        }
    }

    func testLocalSearchAndFriendLensChangeVisibleShops() async throws {
        let data = try XCTUnwrap(PresentationDemo.dataset)
        let results = try await GoogleRestaurantSearch.search(term: "飲食店", region: PresentationDemo.initialRegion, genre: .all, nearby: false)
        XCTAssertEqual(results.count, 6)
        let curry = try await GoogleRestaurantSearch.search(term: "チャンピオン", region: PresentationDemo.initialRegion, genre: .all, nearby: false)
        XCTAssertEqual(curry.count, 1)
        let cafe = PresentationDemo.search(term: "カフェ", region: PresentationDemo.initialRegion, genre: .cafe, nearby: false)
        XCTAssertEqual(cafe.count, 1)
        XCTAssertTrue(PresentationDemo.search(term: "該当なし", region: PresentationDemo.initialRegion, genre: .all, nearby: false).isEmpty)
        let favoriteIDs = FriendLens(mode: .favoriteFriends).includedFriendIDs(friends: data.friends, favorites: data.favoriteFriendIDs)
        XCTAssertEqual(data.restaurants.filter { data.summary(for: $0, friendIDs: favoriteIDs).count > 0 }.count, 3)
    }

    func testPresentationStoreNeverUsesBackendOrGuestCredentials() async throws {
        let credentials = GuestCredentialStore(service: "jp.meshinowa.presentation.tests.\(UUID().uuidString)")
        defer { credentials.delete(); BackendURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendURLProtocol.self]
        BackendURLProtocol.handler = { _ in
            XCTFail("発表デモからバックエンドへ送信してはいけません")
            return (500, Data())
        }
        let backend = CloudflareBackend(configuration: BackendConfiguration(url: URL(string: "https://api.example.test")!), session: URLSession(configuration: config))
        let data = try XCTUnwrap(PresentationDemo.dataset)
        let store = FriendStore(backend: backend, credentials: credentials, presentation: data)
        let shop = try XCTUnwrap(data.restaurants.first)
        let review = LocalReview(restaurant: SavedRestaurant(item: shop.mapItem), rating: 4.5, comment: "発表用", createdAt: .now, updatedAt: .now)
        await store.start(sharing: [review])
        await store.refresh()
        try await store.upload(review)
        try await store.removeReview(for: review.restaurant)
        XCTAssertNil(credentials.load())
        XCTAssertEqual(store.status, .ready)
        XCTAssertTrue(store.isAvailable)
        XCTAssertTrue(store.isPresentation)
        let friend = try XCTUnwrap(store.friends.first)
        await store.setFavorite(friend, false)
        XCTAssertFalse(store.dataset.favoriteFriendIDs.contains(friend.id))
        await store.remove(friend)
        XCTAssertFalse(store.dataset.reviews.contains { $0.friendID == friend.id })
        store.resetPresentation()
        XCTAssertEqual(store.friends.count, 6)
        XCTAssertEqual(store.dataset.reviews.count, 12)
    }

    func testPersonalSeedsAreRepeatableAndStayInTheirOwnStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = SavedRestaurantStore(fileURL: directory.appendingPathComponent("saved.json"))
        let reviews = LocalReviewStore(fileURL: directory.appendingPathComponent("reviews.json"))
        try PresentationDemo.seedPersonalRecords(saved: saved, reviews: reviews)
        try PresentationDemo.seedPersonalRecords(saved: saved, reviews: reviews)
        XCTAssertEqual(saved.restaurants.count, 3)
        XCTAssertEqual(reviews.reviews.count, 2)
    }
#endif
}
