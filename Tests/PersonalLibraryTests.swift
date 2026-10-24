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
        saved.isFavorite = true
        let reviewedOnly = restaurant("レビューだけのお店")
        let reviews = [saved, reviewedOnly].map {
            LocalReview(restaurant: $0, rating: 4, comment: "", createdAt: .now, updatedAt: .now)
        }
        let merged = PersonalLibrary.restaurants(saved: [saved], reviews: reviews)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.id == saved.id }?.isFavorite, true)
        XCTAssertEqual(merged.first { $0.id == reviewedOnly.id }?.status, .visited)
    }
}
