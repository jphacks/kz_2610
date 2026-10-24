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
}
