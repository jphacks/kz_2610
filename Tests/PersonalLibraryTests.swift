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

    func testDifferentGooglePlacesAreNotMerged() {
        let a = restaurant("同じ名前"), b = restaurant("同じ名前")
        let itemA = a.mapItem; itemA.googleDetails = GoogleRestaurantDetails(placeID: "A")
        let itemB = b.mapItem; itemB.googleDetails = GoogleRestaurantDetails(placeID: "B")
        XCTAssertFalse(SavedRestaurant(item: itemA).isSameStore(as: SavedRestaurant(item: itemB)))
    }
}
