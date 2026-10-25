import MapKit
import UIKit
import XCTest
@testable import meshinowa

@MainActor
final class RestaurantPhotoStoreTests: XCTestCase {
    private func item(_ id: String) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 139)))
        item.name = "架空の店舗"
        item.googleDetails = GoogleRestaurantDetails(placeID: id)
        return item
    }
    private var photo: LoadedRestaurantPhoto { LoadedRestaurantPhoto(image: UIImage()) }

    func testConcurrentViewsAndReturningDetailShareOneRequest() async throws {
        var calls = 0
        let photo = photo
        let store = RestaurantPhotoStore { _ in
            calls += 1
            try await Task.sleep(for: .milliseconds(20))
            return photo
        }
        async let first = store.photo(for: item("one"))
        async let second = store.photo(for: item("one"))
        _ = try await (first, second)
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(store.cachedPhoto(for: item("one")))
        _ = try await store.photo(for: item("one"))
        XCTAssertEqual(calls, 1)
        XCTAssertNil(store.cachedPhoto(for: item("another")))
    }

    func testSessionExpiryForcesRefresh() async throws {
        var now = Date(timeIntervalSince1970: 0)
        var calls = 0
        let photo = photo
        let store = RestaurantPhotoStore(now: { now }) { _ in calls += 1; return photo }
        _ = try await store.photo(for: item("one"))
        now.addTimeInterval(121)
        XCTAssertNil(store.cachedPhoto(for: item("one")))
        _ = try await store.photo(for: item("one"))
        XCTAssertEqual(calls, 2)
    }

    func testEmptyResultsAreBrieflyReusedAndErrorsCanRetry() async throws {
        var now = Date(timeIntervalSince1970: 0)
        var calls = 0
        let store = RestaurantPhotoStore(now: { now }) { _ in
            calls += 1
            if calls == 2 { throw URLError(.notConnectedToInternet) }
            return nil
        }
        _ = try await store.photo(for: item("one"))
        _ = try await store.photo(for: item("one"))
        XCTAssertEqual(calls, 1)
        now.addTimeInterval(31)
        do {
            _ = try await store.photo(for: item("one"))
            XCTFail("Expected network error")
        } catch { }
        _ = try await store.photo(for: item("one"))
        XCTAssertEqual(calls, 3)
    }

    func testPrefetchOnlyLoadsNeighborsAcrossLoopBoundary() async {
        var ids: [String] = []
        let photo = photo
        let store = RestaurantPhotoStore { item in ids.append(item.googleDetails!.placeID); return photo }
        await store.prepareCarousel(items: (0..<5).map { item(String($0)) }, selectedIndex: 0)
        XCTAssertEqual(ids.first, "0")
        XCTAssertEqual(Set(ids), ["0", "1", "4"])
        XCTAssertEqual(ids.count, 3)
        await store.prepareCarousel(items: [item("0"), item("1")], selectedIndex: 0)
        XCTAssertEqual(ids.count, 3)
    }

    func testRequestsHaveBoundedConcurrency() async throws {
        var active = 0
        var peak = 0
        let photo = photo
        let store = RestaurantPhotoStore { _ in
            active += 1
            peak = max(peak, active)
            defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(20))
            return photo
        }
        let items = (0..<8).map { item(String($0)) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for item in items { group.addTask { _ = try await store.photo(for: item) } }
            try await group.waitForAll()
        }
        XCTAssertEqual(peak, 3)
        XCTAssertEqual(active, 0)
    }
}
