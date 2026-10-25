import MapKit
import XCTest
@testable import meshinowa

final class FoodGenreTests: XCTestCase {
    func testPlaceTypesWinOverName() {
        XCTAssertEqual(FoodGenre.infer(name: "こもれび食堂", category: nil, placeTypes: ["ramen_restaurant"]), .noodle)
    }

    func testNameKeywords() {
        XCTAssertEqual(FoodGenre.infer(name: "鮨 なぎさ", category: nil), .sushi)
        XCTAssertEqual(FoodGenre.infer(name: "めん処 ひだまり", category: nil), .noodle)
        XCTAssertEqual(FoodGenre.infer(name: "酒場 ともしび", category: nil), .izakaya)
        XCTAssertEqual(FoodGenre.infer(name: "こもれび食堂", category: nil), .washoku)
        XCTAssertEqual(FoodGenre.infer(name: "Bistro Cafe Aoba", category: nil), .cafe)
    }

    func testMapKitCategoryIsTheFallback() {
        XCTAssertEqual(FoodGenre.infer(name: "つむぎ", category: MKPointOfInterestCategory.bakery.rawValue), .bread)
        XCTAssertEqual(FoodGenre.infer(name: "まるい", category: MKPointOfInterestCategory.cafe.rawValue), .cafe)
        XCTAssertEqual(FoodGenre.infer(name: "ひだまり", category: MKPointOfInterestCategory.restaurant.rawValue), .other)
        XCTAssertEqual(FoodGenre.infer(name: nil, category: nil), .other)
    }
}
