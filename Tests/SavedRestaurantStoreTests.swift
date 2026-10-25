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
        store.setLiked(item, isLiked: true)
        let reloaded = SavedRestaurantStore(fileURL: url)
        XCTAssertTrue(reloaded.contains(item))
        XCTAssertEqual(reloaded.restaurants.first?.name, item.name)
        XCTAssertEqual(reloaded.restaurants.first?.mapItem.placemark.coordinate.latitude, 35.6812)
    }

    @MainActor func testRepeatedSearchResultDoesNotDuplicateSavedPlace() async throws {
        let store = SavedRestaurantStore(fileURL: try temporaryURL())
        store.setLiked(restaurant(), isLiked: true)
        store.setLiked(restaurant(name: " テスト食堂 ", latitude: 35.681201), isLiked: true)
        XCTAssertEqual(store.restaurants.count, 1)
        store.setLiked(restaurant(name: "別の食堂"), isLiked: true)
        XCTAssertEqual(store.restaurants.count, 2)
    }

    @MainActor func testRemovalSurvivesStoreRecreation() async throws {
        let url = try temporaryURL()
        let store = SavedRestaurantStore(fileURL: url)
        let item = restaurant()
        store.setLiked(item, isLiked: true)
        store.setLiked(item, isLiked: false)
        XCTAssertFalse(SavedRestaurantStore(fileURL: url).contains(item))
    }

    @MainActor func testCorruptDataIsNotOverwritten() async throws {
        let url = try temporaryURL()
        let original = Data("not valid JSON".utf8)
        try original.write(to: url)
        let store = SavedRestaurantStore(fileURL: url)
        store.setLiked(restaurant(), isLiked: true)
        XCTAssertTrue(store.restaurants.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor func testFailedWriteDoesNotShowPlaceAsSaved() async throws {
        let url = try temporaryURL()
        // 保存先の親がフォルダではなくファイルなので、書き込みは失敗する。
        try Data().write(to: url)
        let store = SavedRestaurantStore(fileURL: url.appendingPathComponent("saved.json"))
        store.setLiked(restaurant(), isLiked: true)
        XCTAssertTrue(store.restaurants.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        try FileManager.default.removeItem(at: url)
        store.setLiked(restaurant(), isLiked: true)
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

    @MainActor func testUnlikeRemovesSavedPlace() async throws {
        let url = try temporaryURL()
        let store = SavedRestaurantStore(fileURL: url)
        let item = restaurant()
        store.setLiked(item, isLiked: true)
        XCTAssertEqual(SavedRestaurantStore(fileURL: url).restaurant(for: item)?.isLiked, true)
        store.setLiked(item, isLiked: false)
        XCTAssertTrue(SavedRestaurantStore(fileURL: url).restaurants.isEmpty)
    }

    /// 以前の保存形式は、行きたい・お気に入り・行ったのどれもいいねに移る（行ったはレビューで表す）。
    @MainActor func testLegacyDataMigratesToLike() async throws {
        let url = try temporaryURL()
        func object(_ name: String, _ fields: [String: Any]) throws -> [String: Any] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(SavedRestaurant(item: restaurant(name: name)))) as? [String: Any])
            object.removeValue(forKey: "isLiked")
            return object.merging(fields) { $1 }
        }
        let objects = [
            try object("最初期のお店", [:]),
            try object("行きたいお店", ["status": "wantToGo", "isFavorite": false]),
            try object("お気に入りのお店", ["status": NSNull(), "isFavorite": true]),
            try object("行ったお店", ["status": "visited", "isFavorite": false]),
            try object("行っただけのお店", ["isLiked": false, "isVisited": true]),
        ]
        try JSONSerialization.data(withJSONObject: objects).write(to: url)
        let store = SavedRestaurantStore(fileURL: url)
        XCTAssertEqual(store.restaurants.filter(\.isLiked).count, 5)
        // 新しい形式で書き直したあとも同じ内容で読める。
        store.setLiked(restaurant(name: "行きたいお店"), isLiked: false)
        let reloaded = SavedRestaurantStore(fileURL: url)
        XCTAssertEqual(reloaded.restaurants.count, 4)
        XCTAssertTrue(reloaded.restaurants.allSatisfy(\.isLiked))
    }

    @MainActor func testCollectionsTreatReviewedPlacesAsVisited() async throws {
        let store = SavedRestaurantStore(fileURL: try temporaryURL())
        let first = restaurant(name: "テスト食堂A"), second = restaurant(name: "テスト食堂B")
        store.setLiked(first, isLiked: true); store.setLiked(second, isLiked: true)
        let reviewedOnly = SavedRestaurant(item: restaurant(name: "テスト食堂C"), isLiked: false)
        let ratings = [SavedRestaurant.identifier(for: second): 5.0, reviewedOnly.id: 3.0]
        let library = store.restaurants + [reviewedOnly]
        let liked = SavedCollectionQuery.results(library, collection: .liked, search: "食堂", sort: .myRating, ratings: ratings)
        XCTAssertEqual(liked.map(\.name), ["テスト食堂B", "テスト食堂A"])
        let unreviewed = SavedCollectionQuery.results(library, collection: .liked, search: "", sort: .name,
                                                      ratings: ratings, unreviewedOnly: true)
        XCTAssertEqual(unreviewed.map(\.name), ["テスト食堂A"])
        let visited = SavedCollectionQuery.results(library, collection: .visited, search: "", sort: .myRating, ratings: ratings)
        XCTAssertEqual(visited.map(\.name), ["テスト食堂B", "テスト食堂C"])
    }
}
