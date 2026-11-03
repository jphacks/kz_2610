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
}
