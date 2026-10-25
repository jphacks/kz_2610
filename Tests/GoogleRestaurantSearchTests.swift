import GooglePlacesSwift
import MapKit
import XCTest
@testable import meshinowa

@MainActor
final class GoogleRestaurantSearchTests: XCTestCase {
    func testCategoryMappingPrioritizesSpecificTypes() {
        XCTAssertEqual(GoogleRestaurantSearch.category(types: [.restaurant, .cafe]), .cafe)
        XCTAssertEqual(GoogleRestaurantSearch.category(types: [.bakery, .cafe]), .bakery)
        XCTAssertEqual(GoogleRestaurantSearch.category(types: [.restaurant]), .restaurant)
        XCTAssertNil(GoogleRestaurantSearch.category(types: []))
    }

    func testSearchKeepsClosedRestaurantsAndRequestsIdentityWithoutBulkPhotos() {
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35, longitude: 139),
                                        latitudinalMeters: 2000, longitudinalMeters: 2000)
        let request = GoogleRestaurantSearch.request(term: "カフェ", region: region, genre: .cafe, nearby: true)
        XCTAssertFalse(request.isOpenNow)
        XCTAssertEqual(request.includedType, .cafe)
        XCTAssertTrue(request.isStrictTypeFiltering)
        XCTAssertTrue(request.placeProperties.contains(.placeID))
        XCTAssertFalse(request.placeProperties.contains(.photos))
    }

    func testSavedPlaceIDSurvivesRoundTripWithoutProviderPhotos() throws {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 139)))
        item.name = "架空の店舗"
        item.googleDetails = GoogleRestaurantDetails(placeID: "synthetic-place-id")
        let data = try JSONEncoder().encode(SavedRestaurant(item: item))
        let decoded = try JSONDecoder().decode(SavedRestaurant.self, from: data)
        XCTAssertEqual(decoded.mapItem.googleDetails?.placeID, "synthetic-place-id")
        XCTAssertNil(decoded.mapItem.googleDetails?.place)
    }

    func testGenreSwitchKeepsKeywordInAreaSearchRequest() {
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35, longitude: 139),
                                        latitudinalMeters: 2000, longitudinalMeters: 2000)
        for genre in [RestaurantGenre.noodle, .sushi, .all] {
            let request = GoogleRestaurantSearch.request(term: genre.searchTerm(for: "ラーメン"),
                                                         region: region, genre: genre, nearby: true)
            XCTAssertTrue(request.textQuery.contains("ラーメン"))
            if genre == .sushi { XCTAssertTrue(request.textQuery.contains("寿司")) }
        }
    }
}
