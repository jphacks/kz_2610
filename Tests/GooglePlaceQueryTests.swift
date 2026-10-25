import GooglePlacesSwift
import MapKit
import SwiftUI
import XCTest
@testable import meshinowa

final class GooglePlaceQueryTests: XCTestCase {
    private func item(name: String? = "架空の食堂", latitude: Double = 35, longitude: Double = 139) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                                    addressDictionary: ["Street": "架空町1-2-3"]))
        item.name = name
        return item
    }

    func testQueryUsesStoreIdentityAndDoesNotExcludeClosedStores() {
        let query = GooglePlaceQuery(item: item())
        XCTAssertTrue(query.isValid)
        XCTAssertTrue(query.request.textQuery.contains(query.name))
        XCTAssertTrue(query.request.textQuery.contains("架空町"))
        XCTAssertFalse(query.request.isOpenNow)
        XCTAssertEqual(query.request.maxResultCount, 1)
        XCTAssertEqual(query.request.rankPreference, .relevance)
    }

    func testMissingStoreNameDoesNotTriggerAnUnrelatedNearbySearch() {
        XCTAssertFalse(GooglePlaceQuery(item: item(name: nil)).isValid)
        XCTAssertFalse(GooglePlaceQuery(item: item(name: "  ")).isValid)
    }

    func testRepeatedViewsKeepTheSameRequestIdentity() {
        let first = GooglePlaceQuery(item: item())
        let second = GooglePlaceQuery(item: item())
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.request.textQuery, second.request.textQuery)
        XCTAssertNotEqual(first, GooglePlaceQuery(item: item(name: "別の架空食堂")))
    }

    @MainActor func testUnconfiguredCardRendersWithoutCallingGoogle() throws {
        guard !GooglePlacesService.isConfigured else { throw XCTSkip("Configured Google key uses live UI Kit") }
        let renderer = ImageRenderer(content: GooglePlaceCard(item: item()).frame(width: 350).padding(16))
        XCTAssertNotNil(renderer.uiImage)
    }
}
