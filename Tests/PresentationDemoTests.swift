import MapKit
import XCTest
@testable import meshinowa

@MainActor
final class PresentationDemoTests: XCTestCase {
    func testNormalBuildDoesNotExposePresentationData() {
#if !PRESENTATION_DEMO
        XCTAssertFalse(PresentationDemo.isEnabled)
        XCTAssertNil(PresentationDemo.dataset)
        XCTAssertTrue(PresentationDemo.targets.isEmpty)
#endif
    }

#if PRESENTATION_DEMO
    /// SDK応答の代わり。単体テストではGoogleに通信せず、実行時と同じ照合・結合だけを試す。
    private func places() -> [String: MKMapItem] {
        let names = ["champion": "カレーのチャンピオン 野々市本店", "higecho": "鬍鬚張魯肉飯 金沢工大前店",
                     "hachiban": "8番らーめん 金沢工大前店", "laterra": "レストラン ラ・テラ", "misdo": "ミスタードーナツ 野々市ショップ"]
        return names.mapValues { name in
            let item = MKMapItem(placemark: MKPlacemark(coordinate: PresentationDemo.initialRegion.center,
                                                       addressDictionary: ["Street": "Googleの応答に含まれる住所"] ))
            item.name = name
            item.pointOfInterestCategory = name.contains("ドーナツ") ? .cafe : .restaurant
            item.googleDetails = GoogleRestaurantDetails(placeID: "test-google-" + name)
            return item
        }
    }

    private func resolve(_ items: [String: MKMapItem]) async throws -> PresentationDemo.Resolution {
        try await PresentationDemo.resolveStores { query in
            guard let target = PresentationDemo.targets.first(where: { $0.query == query }), let item = items[target.key] else { return [] }
            return [item]
        }
    }

    func testInitialDataHasFriendsButNoInventedShopsOrReviews() throws {
        let data = try XCTUnwrap(PresentationDemo.dataset)
        XCTAssertEqual(data.friends.count, 6)
        XCTAssertTrue(data.restaurants.isEmpty)
        XCTAssertTrue(data.reviews.isEmpty)
    }

    func testReviewsUseGoogleIdentityLocationAndProviderDetails() async throws {
        let google = places()
        let result = try await resolve(google)
        let data = result.dataset
        XCTAssertTrue(result.missingNames.isEmpty)
        XCTAssertEqual(data.restaurants.count, 5)
        XCTAssertEqual(data.reviews.count, 12)
        for item in google.values {
            let shop = try XCTUnwrap(data.restaurants.first { $0.id == SavedRestaurant.identifier(for: item) })
            XCTAssertTrue(shop.mapItem === item)
            XCTAssertEqual(shop.name, item.name)
            XCTAssertEqual(shop.coordinate.latitude, item.placemark.coordinate.latitude)
            XCTAssertEqual(shop.coordinate.longitude, item.placemark.coordinate.longitude)
            XCTAssertEqual(shop.mapItem.googleDetails?.placeID, item.googleDetails?.placeID)
        }
        for review in data.reviews {
            XCTAssertTrue(data.friends.contains { $0.id == review.friendID })
            XCTAssertTrue(data.restaurants.contains { $0.id == review.restaurantID })
            XCTAssertTrue((1...5).contains(review.rating))
            XCTAssertEqual(review.rating * 2, floor(review.rating * 2))
            XCTAssertTrue(review.dish.isEmpty)
        }
        let favoriteIDs = FriendLens(mode: .favoriteFriends).includedFriendIDs(friends: data.friends, favorites: data.favoriteFriendIDs)
        XCTAssertEqual(data.restaurants.filter { data.summary(for: $0, friendIDs: favoriteIDs).count > 0 }.count, 3)
    }

    func testUnavailablePlacesAreOmittedInsteadOfUsingHardcodedCoordinates() async throws {
        var google = places()
        google.removeValue(forKey: "laterra")
        let result = try await resolve(google)
        XCTAssertEqual(result.missingNames.count, 1)
        XCTAssertEqual(result.dataset.restaurants.count, 4)
        XCTAssertEqual(result.dataset.reviews.count, 10)
        do {
            _ = try await resolve([:])
            XCTFail("取得できない店舗をモックで補完してはいけません")
        } catch { XCTAssertTrue(error is PresentationDemo.DemoError) }
    }

    func testNamesCoordinatesAndGooglePlaceIDsAreRequiredForMatching() throws {
        let item = try XCTUnwrap(places()["champion"])
        let target = try XCTUnwrap(PresentationDemo.targets.first)
        XCTAssertTrue(target.matches(item))
        item.name = "別のお店"
        XCTAssertFalse(target.matches(item))
        item.name = "カレーのチャンピオン 野々市本店"
        item.googleDetails = nil
        XCTAssertFalse(target.matches(item))
        let distant = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)))
        distant.name = item.name
        distant.googleDetails = GoogleRestaurantDetails(placeID: "other-city")
        XCTAssertFalse(target.matches(distant))
    }

    func testPresentationResolvesOnceAndNeverUsesCloudflareOrGuestCredentials() async throws {
        let credentials = GuestCredentialStore(service: "jp.meshinowa.presentation.tests.\(UUID().uuidString)")
        defer { credentials.delete(); BackendURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendURLProtocol.self]
        BackendURLProtocol.handler = { _ in
            XCTFail("友達のモックをCloudflareへ送信してはいけません")
            return (500, Data())
        }
        let backend = CloudflareBackend(configuration: BackendConfiguration(url: URL(string: "https://api.example.test")!), session: URLSession(configuration: config))
        let resolved = try await resolve(places())
        var loads = 0
        let store = FriendStore(backend: backend, credentials: credentials, presentation: PresentationDemo.dataset,
                                presentationLoader: { loads += 1; return resolved })
        await store.start(sharing: [])
        await store.refresh()
        XCTAssertEqual(loads, 1)
        let shop = try XCTUnwrap(store.dataset.restaurants.first)
        let review = LocalReview(restaurant: SavedRestaurant(item: shop.mapItem), rating: 4.5, comment: "手入力の記録", createdAt: .now, updatedAt: .now)
        try await store.upload(review)
        try await store.removeReview(for: review.restaurant)
        XCTAssertNil(credentials.load())
        XCTAssertEqual(store.status, .ready)
        let friend = try XCTUnwrap(store.friends.first)
        await store.setFavorite(friend, false)
        XCTAssertFalse(store.dataset.favoriteFriendIDs.contains(friend.id))
        await store.remove(friend)
        XCTAssertFalse(store.dataset.reviews.contains { $0.friendID == friend.id })
        store.resetPresentation()
        XCTAssertEqual(store.dataset.reviews.count, 12)
        await store.refresh(force: true)
        XCTAssertEqual(loads, 2)
    }

    func testMigrationRemovesOnlyOldPersonalSamplesAndDoesNotSeedNewOnes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = SavedRestaurantStore(fileURL: directory.appendingPathComponent("saved.json"))
        let reviews = LocalReviewStore(fileURL: directory.appendingPathComponent("reviews.json"))
        try PresentationDemo.removeLegacyPersonalSamples(saved: saved, reviews: reviews)
        XCTAssertTrue(saved.restaurants.isEmpty)
        XCTAssertTrue(reviews.reviews.isEmpty)
        let google = places()
        let sample = try XCTUnwrap(google["champion"])
        let manual = try XCTUnwrap(google["misdo"])
        try reviews.save(item: sample, rating: 4.5, comment: "発表用サンプル：友達とまた行きたいお店。")
        try reviews.save(item: manual, rating: 5, comment: "手入力した記録")
        saved.setLiked(sample, isLiked: true)
        saved.setLiked(manual, isLiked: true)
        try PresentationDemo.removeLegacyPersonalSamples(saved: saved, reviews: reviews)
        XCTAssertEqual(reviews.reviews.map(\.restaurant.name), [manual.name])
        XCTAssertEqual(saved.restaurants.map(\.name), [manual.name])
    }
#endif
}
