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

@MainActor
final class RestaurantSearchSessionTests: XCTestCase {
    private let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76),
                                             latitudinalMeters: 2000, longitudinalMeters: 2000)

    func testDisplayedResultIsReusedButExplicitRefreshFetchesAgain() async throws {
        var calls = 0
        let item = MKMapItem(placemark: MKPlacemark(coordinate: region.center))
        let session = RestaurantSearchSession { _, _, _, _ in calls += 1; return [item] }
        _ = try await session.search(term: "カフェ", region: region, genre: .cafe, nearby: true)
        let repeated = try await session.search(term: "カフェ", region: region, genre: .cafe, nearby: true)
        XCTAssertTrue(repeated.first === item)
        XCTAssertEqual(calls, 1)
        _ = try await session.search(term: "カフェ", region: region, genre: .cafe, nearby: true, force: true)
        XCTAssertEqual(calls, 2)
    }

    func testChangedConditionsAndAreaFetchAgainAndOldResultsAreNotKept() async throws {
        var calls = 0
        let session = RestaurantSearchSession { _, _, _, _ in calls += 1; return [] }
        _ = try await session.search(term: "飲食店", region: region, genre: .all, nearby: true)
        _ = try await session.search(term: "飲食店", region: region, genre: .all, nearby: true)
        XCTAssertEqual(calls, 1) // 空の検索結果も、繰り返し通信せず表示できる。
        _ = try await session.search(term: "カフェ", region: region, genre: .cafe, nearby: true)
        _ = try await session.search(term: "飲食店", region: region, genre: .all, nearby: true)
        var moved = region
        moved.center.latitude += 0.01
        _ = try await session.search(term: "飲食店", region: moved, genre: .all, nearby: true)
        _ = try await session.search(term: "飲食店", region: moved, genre: .all, nearby: false)
        XCTAssertEqual(calls, 5)
    }

    func testConcurrentRequestsShareOneFetch() async throws {
        var calls = 0
        let session = RestaurantSearchSession { _, _, _, _ in
            calls += 1
            try await Task.sleep(for: .milliseconds(20))
            return []
        }
        async let first = session.search(term: "カフェ", region: region, genre: .cafe, nearby: true)
        async let second = session.search(term: "カフェ", region: region, genre: .cafe, nearby: true)
        _ = try await (first, second)
        XCTAssertEqual(calls, 1)
    }

    func testLateResultCannotReplaceNewSearch() async throws {
        var continuations: [String: CheckedContinuation<[MKMapItem], Error>] = [:]
        var calls = 0
        let session = RestaurantSearchSession { term, _, _, _ in
            calls += 1
            return try await withCheckedThrowingContinuation { continuations[term] = $0 }
        }
        let old = Task { try await session.search(term: "古い条件", region: region, genre: .all, nearby: true) }
        while continuations["古い条件"] == nil { await Task.yield() }
        let recent = Task { try await session.search(term: "新しい条件", region: region, genre: .all, nearby: true) }
        while continuations["新しい条件"] == nil { await Task.yield() }
        continuations["新しい条件"]?.resume(returning: [])
        _ = try await recent.value
        continuations["古い条件"]?.resume(returning: [])
        do { _ = try await old.value; XCTFail("古い検索の結果を採用してはいけません") }
        catch { XCTAssertTrue(error is CancellationError) }
        _ = try await session.search(term: "新しい条件", region: region, genre: .all, nearby: true)
        XCTAssertEqual(calls, 2)
    }
}

@MainActor
final class MapAreaNamerTests: XCTestCase {
    func testAreaNamePrefersLocalityThenAdministrativeArea() {
        XCTAssertEqual(MapAreaNamer.Area(subLocality: "丸の内", locality: "千代田区", administrativeArea: "東京都").name, "丸の内")
        XCTAssertEqual(MapAreaNamer.Area(subLocality: " ", locality: "千代田区", administrativeArea: "東京都").name, "千代田区")
        XCTAssertEqual(MapAreaNamer.Area(subLocality: nil, locality: nil, administrativeArea: "東京都").name, "東京都")
        XCTAssertNil(MapAreaNamer.Area(subLocality: nil, locality: nil, administrativeArea: nil).name)
    }

    func testNearbyCenterDoesNotRepeatRequest() async {
        var calls = 0
        let namer = MapAreaNamer { _ in
            calls += 1
            return .init(subLocality: "丸の内", locality: nil, administrativeArea: nil)
        }
        namer.update(center: .init(latitude: 35.681, longitude: 139.767))
        for _ in 0..<20 where namer.name == nil { await Task.yield() }
        namer.update(center: .init(latitude: 35.682, longitude: 139.767))
        await Task.yield()
        XCTAssertEqual(namer.name, "丸の内")
        XCTAssertEqual(calls, 1)
        namer.update(center: .init(latitude: 35.69, longitude: 139.767))
        for _ in 0..<20 where calls < 2 { await Task.yield() }
        XCTAssertEqual(calls, 2)
    }

    func testOldResultDoesNotOverrideNewCenter() async {
        var pending: [CheckedContinuation<MapAreaNamer.Area?, Error>] = []
        let namer = MapAreaNamer { _ in
            try await withCheckedThrowingContinuation { pending.append($0) }
        }
        namer.update(center: .init(latitude: 35.681, longitude: 139.767))
        for _ in 0..<20 where pending.count < 1 { await Task.yield() }
        XCTAssertEqual(pending.count, 1)
        guard pending.count == 1 else { return }
        namer.invalidate()
        namer.update(center: .init(latitude: 35.69, longitude: 139.767))
        for _ in 0..<20 where pending.count < 2 { await Task.yield() }
        XCTAssertEqual(pending.count, 2)
        guard pending.count == 2 else { pending[0].resume(returning: nil); return }
        pending[1].resume(returning: .init(subLocality: "新しい地域", locality: nil, administrativeArea: nil))
        for _ in 0..<20 where namer.name == nil { await Task.yield() }
        pending[0].resume(returning: .init(subLocality: "古い地域", locality: nil, administrativeArea: nil))
        await Task.yield()
        XCTAssertEqual(namer.name, "新しい地域")
    }
}
