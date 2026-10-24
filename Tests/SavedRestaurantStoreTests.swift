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
}
