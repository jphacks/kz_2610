import MapKit
import XCTest
@testable import meshinowa

final class PersonalLibraryTests: XCTestCase {
    private func restaurant(_ name: String) -> SavedRestaurant {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 139)))
        item.name = name
        return SavedRestaurant(item: item)
    }

    func testMyMapMergesSavedAndReviewedPlacesWithoutDuplicates() {
        var saved = restaurant("保存したお店")
        let reviewedOnly = restaurant("レビューだけのお店")
        let reviews = [saved, reviewedOnly].map {
            LocalReview(restaurant: $0, rating: 4, comment: "", createdAt: .now, updatedAt: .now)
        }
        let merged = PersonalLibrary.restaurants(saved: [saved], reviews: reviews)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.id == saved.id }?.isLiked, true)
        XCTAssertEqual(merged.first { $0.id == reviewedOnly.id }?.isLiked, false)
    }

    /// Google に切り替える前に保存したお店と、あとから Google の ID で記録したお店を同じお店として扱う。
    func testLegacyAndGoogleIDsOfTheSameStoreAreMerged() {
        let legacy = restaurant("こもれび食堂")
        let item = legacy.mapItem
        item.googleDetails = GoogleRestaurantDetails(placeID: "abc123")
        let google = SavedRestaurant(item: item)
        XCTAssertNotEqual(legacy.id, google.id)
        let review = LocalReview(restaurant: google, rating: 4.5, comment: "", createdAt: .now, updatedAt: .now)

        let merged = PersonalLibrary.restaurants(saved: [legacy], reviews: [review])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(PersonalLibrary.ratings(for: merged, reviews: [review])[legacy.id], 4.5)
        XCTAssertTrue(PersonalLibrary.reviewedKeys([review]).contains(legacy.id))

        let liked = SavedCollectionQuery.results(merged, collection: .liked, search: "", sort: .newest,
                                                 ratings: PersonalLibrary.ratings(for: merged, reviews: [review]),
                                                 unreviewedOnly: true)
        XCTAssertTrue(liked.isEmpty, "レビュー済みのお店は未レビューに出ない")
    }

    func testShortAddressKeepsBuildingAndDoesNotGuessUnknownAreas() {
        let address = "〒100-0005 東京都千代田区丸の内２丁目７−２ KITTE 6F 日本"
        XCTAssertEqual(address.restaurantLocalAddress, "丸の内２丁目７−２ KITTE 6F")
        XCTAssertEqual(address.restaurantArea, "丸の内２丁目")
        XCTAssertEqual("東京都中央区日本橋1丁目1−1".restaurantArea, "日本橋1丁目")
        XCTAssertEqual("石川県野々市市扇が丘7−1".restaurantArea, "石川県野々市市扇が丘7−1")
        XCTAssertEqual("住所の情報がありません".restaurantArea, "住所の情報がありません")
    }

    func testDifferentGooglePlacesAreNotMerged() {
        let a = restaurant("同じ名前"), b = restaurant("同じ名前")
        let itemA = a.mapItem; itemA.googleDetails = GoogleRestaurantDetails(placeID: "A")
        let itemB = b.mapItem; itemB.googleDetails = GoogleRestaurantDetails(placeID: "B")
        XCTAssertFalse(SavedRestaurant(item: itemA).isSameStore(as: SavedRestaurant(item: itemB)))
    }
}
