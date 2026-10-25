import MapKit
import SwiftUI
import UIKit
import XCTest
@testable import meshinowa

final class RestaurantPhotoStoreTests: XCTestCase {
    private let query = RestaurantPhotoQuery(name: "架空の食堂", latitude: 35, longitude: 139)

    @MainActor private func fixture() throws -> RestaurantPhotoAsset {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let photo = try decoder.decode(HotPepperPhoto.self, from: Data("""
        {"shop_id":"J000000001","name":"架空の食堂",
         "image_url":"https://imgfp.hotp.jp/IMGH/fixture/l.jpg",
         "thumbnail_url":"https://imgfp.hotp.jp/IMGH/fixture/s.jpg",
         "shop_url":"https://www.hotpepper.jp/strJ000000001/"}
        """.utf8))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return RestaurantPhotoAsset(photo: photo, image: image)
    }

    @MainActor func testPhotoAndAttributionLayoutForVisualReview() async throws {
        let asset = try fixture()
        let store = RestaurantPhotoStore(loader: { _ in asset })
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 139)))
        item.name = query.name
        _ = await store.asset(for: RestaurantPhotoQuery(item: item))
        let content = VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 12) {
                RestaurantPhotoView(item: item, width: 84, height: 84, store: store)
                Text("架空の食堂\n店舗カードの表示テスト")
                    .font(MeshinowaFont.text(17))
            }
            RestaurantPhotoView(item: item, height: 180, store: store)
        }
        .padding(20)
        .frame(width: 375)
        .background(MeshinowaTheme.paper)
        .environment(\.dynamicTypeSize, .xxxLarge)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("hotpepper-layout.png"))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Hot Pepper photo attribution at large text size (synthetic image)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testRepeatedScreensShareInFlightRequestAndCachedImage() async throws {
        let expected = try fixture()
        let gate = Gate()
        let started = expectation(description: "one shared fetch")
        var calls = 0
        let store = RestaurantPhotoStore(loader: { _ in
            calls += 1
            started.fulfill()
            await gate.wait()
            return expected
        })
        async let first = store.asset(for: query)
        async let second = store.asset(for: query)
        await fulfillment(of: [started], timeout: 2)
        gate.release()
        let assets = await [first, second]
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(assets.allSatisfy { $0?.image === expected.image })
        XCTAssertTrue(store.cached(for: query)?.image === expected.image)
        _ = await store.asset(for: query)
        XCTAssertEqual(calls, 1)
    }

    @MainActor func testExpiredPhotosRefreshAndMissingPhotosAreNotPermanent() async throws {
        let expected = try fixture()
        var date = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0
        let store = RestaurantPhotoStore(loader: { _ in calls += 1; return calls == 1 ? nil : expected }, clock: { date })
        let first = await store.asset(for: query)
        XCTAssertNil(first)
        _ = await store.asset(for: query)
        XCTAssertEqual(calls, 1)
        date.addTimeInterval(301)
        let found = await store.asset(for: query)
        XCTAssertNotNil(found)
        XCTAssertEqual(calls, 2)
        date.addTimeInterval(3601)
        XCTAssertNil(store.cached(for: query))
        _ = await store.asset(for: query)
        XCTAssertEqual(calls, 3)
    }

    @MainActor func testTransientFailuresCanRetryAndInvalidQueriesNeverFetch() async throws {
        var date = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0
        let store = RestaurantPhotoStore(loader: { _ in calls += 1; throw URLError(.notConnectedToInternet) }, clock: { date })
        _ = await store.asset(for: query)
        _ = await store.asset(for: query)
        XCTAssertEqual(calls, 1)
        date.addTimeInterval(31)
        _ = await store.asset(for: query)
        XCTAssertEqual(calls, 2)
        for invalid in [RestaurantPhotoQuery(name: "  ", latitude: 35, longitude: 139),
                        RestaurantPhotoQuery(name: "fixture", latitude: 91, longitude: 139),
                        RestaurantPhotoQuery(name: "fixture", latitude: .nan, longitude: 139)] {
            _ = await store.asset(for: invalid)
        }
        XCTAssertEqual(calls, 2)
    }

    @MainActor func testScrollingLimitsConcurrentDownloads() async {
        let gate = Gate()
        let started = expectation(description: "four active requests")
        started.expectedFulfillmentCount = 4
        var active = 0
        var maximum = 0
        var count = 0
        let store = RestaurantPhotoStore(loader: { _ in
            active += 1; count += 1; maximum = max(maximum, active)
            if count <= 4 { started.fulfill() }
            await gate.wait()
            active -= 1
            return nil
        })
        let tasks = (0..<8).map { index in
            Task { await store.asset(for: RestaurantPhotoQuery(name: "架空\(index)", latitude: 35, longitude: 139)) }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(active, 4)
        gate.release()
        for task in tasks { _ = await task.value }
        XCTAssertEqual(count, 8)
        XCTAssertLessThanOrEqual(maximum, 4)
    }

    func testRemoteImageURLsCannotTargetOtherHostsOrCarryCredentials() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for url in ["https://attacker.example.test/a.jpg", "https://imgfp.hotp.jp.attacker.example.test/a.jpg",
                    "http://imgfp.hotp.jp/a.jpg", "https://fixture:secret@imgfp.hotp.jp/a.jpg"] {
            let payload = ["shop_id": "J000000001", "name": "fixture", "image_url": url,
                           "thumbnail_url": "https://imgfp.hotp.jp/s.jpg", "shop_url": "https://www.hotpepper.jp/strJ000000001/"]
            let photo = try decoder.decode(HotPepperPhoto.self, from: JSONEncoder().encode(payload))
            XCTAssertFalse(photo.hasSafeURLs)
        }
    }
}

@MainActor private final class Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
