import MapKit
import XCTest
@testable import meshinowa

final class RestaurantGenreTests: XCTestCase {
    private func item(_ category: MKPointOfInterestCategory?) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: 35.6812, longitude: 139.7671
        )))
        item.pointOfInterestCategory = category
        return item
    }

    func testUnknownCategoryIsOnlyVisibleWithoutFilter() {
        let unknown = item(nil)
        XCTAssertTrue(RestaurantGenre.all.matches(unknown))
        for genre in RestaurantGenre.allCases where genre != .all {
            XCTAssertFalse(genre.matches(unknown))
        }
    }

    func testCafeFilterDoesNotIncludeRestaurantsOrBakeries() {
        let items = [item(.restaurant), item(.cafe), item(.bakery), item(.cafe)]
        let filtered = items.filter { RestaurantGenre.cafe.matches($0) }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.pointOfInterestCategory == .cafe })
    }

    func testClearingFilterRestoresAllCandidates() {
        let items = [item(.restaurant), item(.cafe), item(.bakery), item(nil)]
        XCTAssertEqual(items.filter { RestaurantGenre.bakery.matches($0) }.count, 1)
        XCTAssertEqual(items.filter { RestaurantGenre.all.matches($0) }.count, 4)
    }
}
