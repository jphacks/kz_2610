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

    func testGenreTabsMatchByName() {
        let ramen = item(.restaurant)
        ramen.name = "中華そば ひだまり"
        XCTAssertTrue(RestaurantGenre.noodle.matches(ramen))
        XCTAssertFalse(RestaurantGenre.sushi.matches(ramen))
    }

    func testSearchedGenreCoversUnknownNames() {
        let place = item(.restaurant)
        place.name = "牛ひとつ"
        XCTAssertFalse(RestaurantGenre.yakiniku.matches(place))
        place.searchedFoodGenre = .yakiniku
        XCTAssertTrue(RestaurantGenre.yakiniku.matches(place))
        XCTAssertEqual(place.foodGenre, .yakiniku)
    }

    func testSearchTermUsesGenreWhenKeywordIsEmpty() {
        XCTAssertEqual(RestaurantGenre.sushi.searchTerm(for: " \n "), "寿司")
        XCTAssertEqual(RestaurantGenre.all.searchTerm(for: ""), "飲食店")
    }

    func testSearchTermKeepsKeywordWithoutDuplicatingGenre() {
        XCTAssertEqual(RestaurantGenre.noodle.searchTerm(for: " ラーメン "), "ラーメン")
        XCTAssertEqual(RestaurantGenre.all.searchTerm(for: " ラーメン "), "ラーメン")
    }
}
