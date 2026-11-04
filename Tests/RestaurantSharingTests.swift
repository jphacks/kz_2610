import MapKit
import SwiftUI
import XCTest
@testable import meshinowa

final class RestaurantSharingTests: XCTestCase {
    func testMapLinkKeepsPlaceIDAndCoordinates() throws {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 35, longitude: 139)))
        item.name = "架空の食堂"
        item.googleDetails = GoogleRestaurantDetails(placeID: "test-place")
        let url = try XCTUnwrap(URLComponents(url: RestaurantSharing.mapURL(for: item), resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.queryItems?.first { $0.name == "query_place_id" }?.value, "test-place")
        XCTAssertTrue(RestaurantSharing.message(for: item).hasPrefix("このお店、おすすめです"))
        XCTAssertTrue(RestaurantSharing.message(for: item, invitation: true).hasPrefix("ここ今度行かない？"))
        XCTAssertEqual(RestaurantSharing.area(for: item), "")
    }

    @MainActor func testCardsRenderAtExportSize() throws {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 35, longitude: 139)))
        item.name = "架空の定食屋・とても長いお店の名前も二行で表示"
        for hasReview in [false, true] {
            let card = RestaurantShareCard(item: item, name: hasReview ? "はるか" : nil,
                                           rating: hasReview ? 4.5 : nil,
                                           comment: hasReview ? String(repeating: "また食べたい、おいしい定食。", count: 10) : nil,
                                           photo: nil)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width * image.scale, 1080)
            XCTAssertEqual(image.size.height * image.scale, 1350)
            let attachment = XCTAttachment(image: image)
            attachment.name = hasReview ? "共有カード・レビューあり" : "共有カード・写真とレビューなし"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor func testShareEditorLayoutAtPhoneSize() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let reviews = LocalReviewStore(fileURL: folder.appendingPathComponent("reviews.json"))
        let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 35, longitude: 139)))
        item.name = "【テスト】喫茶こはる"
        try reviews.save(item: item, rating: 4.5, comment: "プリンとコーヒーの組み合わせがおすすめ。")
        let editor = RestaurantShareCardEditor(item: item)
            .environmentObject(reviews).environmentObject(FriendStore(backend: nil))
        let controller = UIHostingController(rootView: editor)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "共有カード・作成画面"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}
