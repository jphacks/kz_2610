import XCTest
@testable import meshinowa

final class SwipeCategoryTests: XCTestCase {
    func testEachCategoryByExactGenre() {
        let expected: [String: SwipeCategory] = [
            "天ぷら": .washoku, "寿司": .sushi, "うどん": .noodle, "ホルモン": .yakiniku, "焼き鳥": .izakaya,
            "ピザ": .yoshoku, "餃子": .chuka, "喫茶店": .cafe, "サンドイッチ": .pan, "ビュッフェ": .other
        ]
        for (genre, category) in expected {
            XCTAssertEqual(SwipeCategory.classify(genre: genre), category, genre)
        }
        XCTAssertEqual(SwipeCategory.allCases.count, 10)
        XCTAssertEqual(SwipeCategory.noodle.rawValue, "noodle")
        XCTAssertEqual(SwipeCategory.noodle.tagName, "#麺")
    }

    func testPartialMatchPrefersLongerWords() {
        XCTAssertEqual(SwipeCategory.classify(genre: "豚骨ラーメン"), .noodle)
        XCTAssertEqual(SwipeCategory.classify(genre: "煮込みハンバーグ"), .yakiniku)   // 「バー」ではない
        XCTAssertEqual(SwipeCategory.classify(genre: "チーズハンバーガー"), .yoshoku)
        XCTAssertEqual(SwipeCategory.classify(genre: "パンケーキ"), .cafe)
    }

    func testMapKitValues() {
        XCTAssertEqual(SwipeCategory.classify(genre: "MKPOICategoryCafe"), .cafe)
        XCTAssertEqual(SwipeCategory.classify(genre: "MKPOICategoryBakery"), .pan)
        XCTAssertEqual(SwipeCategory.classify(genre: "MKPOICategoryBrewery"), .izakaya)
        XCTAssertEqual(SwipeCategory.classify(genre: "MKPOICategoryNightlife"), .izakaya)
        XCTAssertEqual(SwipeCategory.classify(genre: "MKPOICategoryRestaurant"), .other)
        XCTAssertEqual(SwipeCategory.classify(genre: "ベーカリー"), .pan)
        // MapKit の値には詳細タグを出さない。
        XCTAssertNil(SwipeCategory.detailGenre(for: "MKPOICategoryCafe"))
        XCTAssertEqual(SwipeCategory.displayName(for: "MKPOICategoryBakery"), "ベーカリー")
    }

    func testUnknownIsOther() {
        XCTAssertEqual(SwipeCategory.classify(genre: nil), .other)
        XCTAssertEqual(SwipeCategory.classify(genre: "  "), .other)
        XCTAssertEqual(SwipeCategory.classify(genre: "宇宙食"), .other)
    }

    func testDetailGenreTag() {
        XCTAssertEqual(SwipeCategory.detailGenre(for: "ラーメン"), "ラーメン")
        XCTAssertNil(SwipeCategory.detailGenre(for: "パン"))   // 大分類と同じ名前
        XCTAssertNil(SwipeCategory.detailGenre(for: nil))
    }

    /// 地図のピン（FoodGenre）と同じ区分・名前になる。
    func testMatchesMapPinGenres() {
        XCTAssertEqual(SwipeCategory(foodGenre: .bread), .pan)
        XCTAssertEqual(SwipeCategory(foodGenre: .noodle), .noodle)
        for genre in FoodGenre.allCases {
            XCTAssertEqual(SwipeCategory(foodGenre: genre).name, genre.title, genre.rawValue)
        }
    }

    /// 地図のピンと同じ判定で決まった大分類を優先し、決まらなければ詳細ジャンルから分類する。
    func testCandidatePrefersMapPinGenre() {
        let candidate = SwipeCandidate(id: "a", name: "麺処", genre: "MKPOICategoryRestaurant", address: nil,
                                       latitude: 35, longitude: 139, reviews: [SwipeFixtures.review("r")],
                                       foodCategory: .noodle)
        XCTAssertEqual(candidate.category, .noodle)
        XCTAssertNil(candidate.detailGenre)
        let unknown = SwipeCandidate(id: "b", name: "店", genre: "ラーメン", address: nil,
                                     latitude: 35, longitude: 139, reviews: [SwipeFixtures.review("r")],
                                     foodCategory: .other)
        XCTAssertEqual(unknown.category, .noodle)
    }
}
