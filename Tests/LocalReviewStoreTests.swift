import MapKit
import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
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

    @MainActor private func photo() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).jpegData(withCompressionQuality: 1) { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    @MainActor func testOptionalFieldsPhotosAndRemovalPersist() async throws {
        let file = try url()
        let store = LocalReviewStore(fileURL: file)
        let item = item()
        let image = photo()
        let visit = Date(timeIntervalSince1970: 100)
        try store.save(item: item, rating: 5, comment: "", dish: "オムライス", wantAgain: true,
                       visitedOn: visit, newPhotos: [image])
        let reloaded = LocalReviewStore(fileURL: file)
        let entry = try XCTUnwrap(reloaded.review(for: item))
        XCTAssertEqual(entry.dish, "オムライス")
        XCTAssertTrue(entry.wantAgain)
        XCTAssertEqual(entry.visitedOn, visit)
        let photoURL = try XCTUnwrap(reloaded.photoURL(try XCTUnwrap(entry.photoFileNames.first)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path))
        XCTAssertThrowsError(try reloaded.save(item: item, rating: 5, comment: "", newPhotos: Array(repeating: image, count: 5)))
        try reloaded.save(item: item, rating: 4, comment: "", retainedPhotoNames: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL.path))
        try reloaded.save(item: item, rating: 4, comment: "", newPhotos: [image])
        let added = try XCTUnwrap(reloaded.photoURL(try XCTUnwrap(reloaded.reviews.first?.photoFileNames.first)))
        try reloaded.delete(id: entry.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: added.path))
    }

    @MainActor func testLegacyReviewWithoutNewFieldsCanBeLoaded() async throws {
        let file = try url()
        let entry = LocalReview(restaurant: SavedRestaurant(item: item()), rating: 4, comment: "旧データ", createdAt: .now, updatedAt: .now)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        for key in ["dish", "wantAgain", "visitedOn", "photoFileNames"] { object.removeValue(forKey: key) }
        try JSONSerialization.data(withJSONObject: [object]).write(to: file)
        let loaded = LocalReviewStore(fileURL: file)
        XCTAssertNil(loaded.loadError)
        XCTAssertEqual(loaded.reviews.first?.dish, "")
        XCTAssertEqual(loaded.reviews.first?.photoFileNames, [])
    }

    @MainActor func testPhotoCodecRemovesGPSMetadata() async throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(photo() as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let withGPS = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(withGPS, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 35.0, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 139.0, kCGImagePropertyGPSLongitudeRef: "E"
        ]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let sanitized = try ReviewPhotoCodec.sanitizedJPEG(from: withGPS as Data)
        let output = try XCTUnwrap(CGImageSourceCreateWithData(sanitized as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [String: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        XCTAssertFalse(ReviewPhotoCodec.isSafeFilename("../other.jpg"))
    }
    @MainActor func testOutboxPersistsDeletesAndDoesNotAcknowledgeANewerEdit() async throws {
        let file = try url()
        let store = LocalReviewStore(fileURL: file)
        let shop = item()
        try store.save(item: shop, rating: 4, comment: "first")
        let inFlight = try XCTUnwrap(store.pending.first)
        try store.save(item: shop, rating: 5, comment: "second")
        XCTAssertEqual(store.pending.count, 1)
        try store.acknowledge(inFlight)
        XCTAssertEqual(store.pending.first?.review?.comment, "second")
        try store.delete(id: try XCTUnwrap(store.reviews.first?.id))
        let reloaded = LocalReviewStore(fileURL: file)
        XCTAssertTrue(reloaded.reviews.isEmpty)
        XCTAssertEqual(reloaded.pending.count, 1)
        XCTAssertNil(reloaded.pending.first?.review)
        try reloaded.acknowledge(try XCTUnwrap(reloaded.pending.first))
        XCTAssertTrue(LocalReviewStore(fileURL: file).pending.isEmpty)
    }

    @MainActor func testLegacyReviewsMigrateIntoDurableOutbox() async throws {
        let file = try url()
        let review = LocalReview(restaurant: SavedRestaurant(item: item()), rating: 4, comment: "old", createdAt: .now, updatedAt: .now)
        try JSONEncoder().encode([review]).write(to: file)
        let store = LocalReviewStore(fileURL: file)
        XCTAssertEqual(store.pending.count, 1)
        XCTAssertEqual(store.reviews.first?.comment, "old")
        try store.acknowledge(try XCTUnwrap(store.pending.first))
        XCTAssertTrue(LocalReviewStore(fileURL: file).pending.isEmpty)
    }

    @MainActor func testFailedRestoreKeepsDocumentAndOriginalPhoto() async throws {
        let file = try url()
        let store = LocalReviewStore(fileURL: file)
        try store.save(item: item(), rating: 4, comment: "original", newPhotos: [photo()])
        let original = try XCTUnwrap(store.reviews.first)
        let name = try XCTUnwrap(original.photoFileNames.first)
        let originalPhoto = try Data(contentsOf: XCTUnwrap(store.photoURL(name)))
        let document = try Data(contentsOf: file)
        XCTAssertThrowsError(try store.replace(with: [original], photos: [name: Data("broken".utf8)]))
        XCTAssertEqual(try Data(contentsOf: file), document)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.photoURL(name))), originalPhoto)
    }

    @MainActor func testProviderIDSurvivesNameAndCoordinateChanges() async throws {
        let store = LocalReviewStore(fileURL: try url())
        let shop = item()
        shop.googleDetails = GoogleRestaurantDetails(placeID: "stable-place")
        try store.save(item: shop, rating: 4, comment: "original")
        shop.name = "renamed"
        XCTAssertEqual(store.review(for: shop)?.comment, "original")
        try store.save(item: shop, rating: 5, comment: "edited")
        XCTAssertEqual(store.reviews.count, 1)
        XCTAssertEqual(store.reviews.first?.rating, 5)
    }

    @MainActor func testRestoreStagesFreshPhotosAndSupportsRollback() async throws {
        let file = try url()
        let store = LocalReviewStore(fileURL: file)
        try store.save(item: item(), rating: 4, comment: "original", newPhotos: [photo()])
        let original = try XCTUnwrap(store.reviews.first)
        let checkpoint = try store.checkpoint()
        let name = try XCTUnwrap(original.photoFileNames.first)
        let bytes = try Data(contentsOf: XCTUnwrap(store.photoURL(name)))
        try store.replace(with: [original], photos: [name: bytes])
        let fresh = try XCTUnwrap(store.reviews.first?.photoFileNames.first)
        XCTAssertNotEqual(name, fresh)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(store.photoURL(name)).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(store.photoURL(fresh)).path))
        try store.restoreCheckpoint(checkpoint)
        XCTAssertEqual(store.reviews.first?.photoFileNames, [name])
    }

    @MainActor func testDatabaseResetRequeuesAcknowledgedReviewsWithoutLosingLocalData() async throws {
        let store = LocalReviewStore(fileURL: try url())
        try store.save(item:item(),rating:4.5,comment:"端末に残すレビュー")
        try store.acknowledge(try XCTUnwrap(store.pending.first))
        XCTAssertTrue(store.pending.isEmpty)
        try store.enqueueAllForSharing()
        XCTAssertEqual(store.pending.count,1)
        XCTAssertEqual(store.pending.first?.review?.comment,"端末に残すレビュー")
        XCTAssertEqual(store.reviews.first?.rating,4.5)
    }

}
