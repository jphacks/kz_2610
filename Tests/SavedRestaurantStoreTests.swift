import MapKit
import XCTest
@testable import meshinowa

final class SavedRestaurantStoreTests: XCTestCase {
    private func temporaryURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("saved.json")
    }

    private func restaurant(name: String = "テスト食堂", latitude: Double = 35.6812) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: latitude, longitude: 139.7671
        )))
        item.name = name
        item.pointOfInterestCategory = .restaurant
        return item
    }

    @MainActor func testSaveSurvivesStoreRecreation() async throws {
        let url = try temporaryURL()
        let item = restaurant()
        let store = SavedRestaurantStore(fileURL: url)
        store.setSaved(item, isSaved: true)
        let reloaded = SavedRestaurantStore(fileURL: url)
        XCTAssertTrue(reloaded.contains(item))
        XCTAssertEqual(reloaded.restaurants.first?.name, item.name)
        XCTAssertEqual(reloaded.restaurants.first?.mapItem.placemark.coordinate.latitude, 35.6812)
    }

    @MainActor func testRepeatedSearchResultDoesNotDuplicateSavedPlace() async throws {
        let store = SavedRestaurantStore(fileURL: try temporaryURL())
        store.setSaved(restaurant(), isSaved: true)
        store.setSaved(restaurant(name: " テスト食堂 ", latitude: 35.681201), isSaved: true)
        XCTAssertEqual(store.restaurants.count, 1)
        store.setSaved(restaurant(name: "別の食堂"), isSaved: true)
        XCTAssertEqual(store.restaurants.count, 2)
    }

    @MainActor func testRemovalSurvivesStoreRecreation() async throws {
        let url = try temporaryURL()
        let store = SavedRestaurantStore(fileURL: url)
        let item = restaurant()
        store.setSaved(item, isSaved: true)
        store.setSaved(item, isSaved: false)
        XCTAssertFalse(SavedRestaurantStore(fileURL: url).contains(item))
    }

    @MainActor func testCorruptDataIsNotOverwritten() async throws {
        let url = try temporaryURL()
        let original = Data("not valid JSON".utf8)
        try original.write(to: url)
        let store = SavedRestaurantStore(fileURL: url)
        store.setSaved(restaurant(), isSaved: true)
        XCTAssertTrue(store.restaurants.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor func testFailedWriteDoesNotShowPlaceAsSaved() async throws {
        let url = try temporaryURL()
        // 保存先の親がフォルダではなくファイルなので、書き込みは失敗する。
        try Data().write(to: url)
        let store = SavedRestaurantStore(fileURL: url.appendingPathComponent("saved.json"))
        store.setSaved(restaurant(), isSaved: true)
        XCTAssertTrue(store.restaurants.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        try FileManager.default.removeItem(at: url)
        store.setSaved(restaurant(), isSaved: true)
        XCTAssertEqual(store.restaurants.count, 1)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor func testSavedPlacesAreNewestFirst() async throws {
        let url = try temporaryURL()
        let first = SavedRestaurant(item: restaurant(name: "先のお店"), savedAt: Date(timeIntervalSince1970: 1))
        let second = SavedRestaurant(item: restaurant(name: "後のお店"), savedAt: Date(timeIntervalSince1970: 2))
        try JSONEncoder().encode([first, second]).write(to: url)
        let store = SavedRestaurantStore(fileURL: url)
        XCTAssertEqual(store.restaurants.map(\.name), ["後のお店", "先のお店"])
    }

    @MainActor func testVisitedReplacesWantButKeepsFavorite() async throws {
        let url = try temporaryURL()
        let store = SavedRestaurantStore(fileURL: url)
        let item = restaurant()
        store.setSaved(item, isSaved: true)
        store.setFavorite(item, isFavorite: true)
        XCTAssertTrue(store.markVisited(item))
        let reloaded = SavedRestaurantStore(fileURL: url)
        XCTAssertEqual(reloaded.restaurant(for: item)?.status, .visited)
        XCTAssertEqual(reloaded.restaurant(for: item)?.isFavorite, true)
        reloaded.setVisitStatus(item, status: nil)
        XCTAssertEqual(reloaded.restaurants.count, 1)
        reloaded.setFavorite(item, isFavorite: false)
        XCTAssertTrue(reloaded.restaurants.isEmpty)
    }

    @MainActor func testLegacySavedPlaceMigratesToWantToGo() async throws {
        let url = try temporaryURL()
        let entry = SavedRestaurant(item: restaurant())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        object.removeValue(forKey: "status"); object.removeValue(forKey: "isFavorite")
        try JSONSerialization.data(withJSONObject: [object]).write(to: url)
        let store = SavedRestaurantStore(fileURL: url)
        XCTAssertEqual(store.restaurants.first?.status, .wantToGo)
        store.setVisitStatus(restaurant(), status: nil)
        store.setFavorite(restaurant(), isFavorite: true)
        XCTAssertNil(SavedRestaurantStore(fileURL: url).restaurants.first?.status)
    }

    @MainActor func testCollectionFilteringAndOwnRatingSort() async throws {
        let store = SavedRestaurantStore(fileURL: try temporaryURL())
        let first = restaurant(name: "テスト食堂A"), second = restaurant(name: "テスト食堂B")
        store.setSaved(first, isSaved: true); store.setSaved(second, isSaved: true)
        store.setFavorite(second, isFavorite: true)
        let ratings = [SavedRestaurant.identifier(for: first): 3.0, SavedRestaurant.identifier(for: second): 5.0]
        let sorted = SavedCollectionQuery.results(store.restaurants, collection: .wantToGo, search: "食堂", sort: .myRating, ratings: ratings)
        XCTAssertEqual(sorted.map(\.name), ["テスト食堂B", "テスト食堂A"])
        XCTAssertEqual(SavedCollectionQuery.results(store.restaurants, collection: .favorites, search: "", sort: .name, ratings: ratings).count, 1)
        store.markVisited(second)
        XCTAssertEqual(store.restaurants.filter(SavedCollection.wantToGo.includes).count, 1)
        XCTAssertEqual(store.restaurants.filter(SavedCollection.visited.includes).count, 1)
    }
}
