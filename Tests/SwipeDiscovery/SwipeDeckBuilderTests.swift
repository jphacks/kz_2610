import XCTest
@testable import meshinowa

final class SwipeDeckBuilderTests: XCTestCase {
    private func build(_ candidates: [SwipeCandidate], radius: Double = 1000, category: SwipeCategory? = nil,
                       decided: Set<String> = [], excluded: Set<String> = []) -> SwipeDeckBuilder.Result {
        SwipeDeckBuilder.build(from: candidates, centerLatitude: SwipeFixtures.tokyo.latitude,
                               centerLongitude: SwipeFixtures.tokyo.longitude, radius: radius,
                               category: category, decidedIDs: decided, isExcluded: { excluded.contains($0) })
    }

    func testOnlyShopsWithinRadiusAreIncluded() {
        let result = build([SwipeFixtures.candidate("near", metersNorth: 900),
                            SwipeFixtures.candidate("far", metersNorth: 1200)])
        XCTAssertEqual(result.candidates.map(\.id), ["near"])
        XCTAssertEqual(result.inRadiusCount, 1)
    }

    func testDecidedSavedAndReviewedShopsAreExcluded() {
        let result = build(["a", "b", "c", "d"].map { SwipeFixtures.candidate($0) },
                           decided: ["a"], excluded: ["b", "c"])
        XCTAssertEqual(result.candidates.map(\.id), ["d"])
        // 「全部見ました」と「近くにない」を区別するため、除外前の数を返す。
        XCTAssertEqual(result.inRadiusCount, 4)
    }

    func testShopsWithoutFriendReviewsAreNeverShown() {
        let empty = SwipeFixtures.candidate("x", reviews: [])
        XCTAssertTrue(build([empty]).candidates.isEmpty)
        XCTAssertEqual(build([empty]).inRadiusCount, 0)
    }

    func testOrderIsAverageRatingThenNewestReview() {
        let high = SwipeFixtures.candidate("high", reviews: [SwipeFixtures.review("1", rating: 5, updatedAt: 1)])
        let oldTie = SwipeFixtures.candidate("old", reviews: [SwipeFixtures.review("2", rating: 4, updatedAt: 10)])
        let newTie = SwipeFixtures.candidate("new", reviews: [SwipeFixtures.review("3", rating: 4, updatedAt: 20)])
        XCTAssertEqual(build([oldTie, newTie, high]).candidates.map(\.id), ["high", "new", "old"])
    }

    func testCategoryFilter() {
        let ramen = SwipeFixtures.candidate("ramen", genre: "ラーメン")
        let cafe = SwipeFixtures.candidate("cafe", genre: "カフェ")
        XCTAssertEqual(build([ramen, cafe], category: .noodle).candidates.map(\.id), ["ramen"])
    }

    func testDistance() {
        let meters = SwipeDeckBuilder.distance(fromLatitude: 35.0, longitude: 139.0, toLatitude: 35.009, longitude: 139.0)
        XCTAssertEqual(meters, 1000, accuracy: 5)
    }
}
