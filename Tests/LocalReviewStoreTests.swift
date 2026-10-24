import MapKit
import XCTest
@testable import meshinowa

final class LocalReviewStoreTests: XCTestCase {
    private func url() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("reviews.json")
    }
    private func item() -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 139)))
        item.name = "架空のテスト食堂"
        return item
    }

    @MainActor func testCreateEditAndDeleteSurviveReload() async throws {
        let file = try url()
        let store = LocalReviewStore(fileURL: file)
        let item = item()
        try store.save(item: item, rating: 4.5, comment: "また行きたい")
        let created = try XCTUnwrap(store.review(for: item)?.createdAt)
        try store.save(item: item, rating: 5, comment: "更新")
        let reloaded = LocalReviewStore(fileURL: file)
        XCTAssertEqual(reloaded.reviews.count, 1)
        XCTAssertEqual(reloaded.review(for: item)?.rating, 5)
        XCTAssertEqual(reloaded.review(for: item)?.createdAt, created)
        try reloaded.delete(id: try XCTUnwrap(reloaded.reviews.first?.id))
        XCTAssertTrue(LocalReviewStore(fileURL: file).reviews.isEmpty)
    }

    @MainActor func testInvalidInputDoesNotReplaceReview() async throws {
        let store = LocalReviewStore(fileURL: try url())
        let item = item()
        try store.save(item: item, rating: 4, comment: "元の内容")
        for rating in [0, 0.5, 4.2, 5.5] {
            XCTAssertThrowsError(try store.save(item: item, rating: rating, comment: ""))
        }
        XCTAssertThrowsError(try store.save(item: item, rating: 5, comment: String(repeating: "あ", count: 301)))
        XCTAssertEqual(store.review(for: item)?.comment, "元の内容")
    }

    @MainActor func testCorruptFileCannotBeOverwritten() async throws {
        let file = try url()
        let original = Data("broken".utf8)
        try original.write(to: file)
        let store = LocalReviewStore(fileURL: file)
        XCTAssertThrowsError(try store.save(item: item(), rating: 5, comment: ""))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
