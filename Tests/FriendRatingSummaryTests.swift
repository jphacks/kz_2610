import XCTest
@testable import meshinowa

final class FriendRatingSummaryTests: XCTestCase {
    private func review(_ id: String, friend: String = "a", restaurant: String = "shop",
                        rating: Double, time: Double = 1) -> FriendReview {
        FriendReview(id: id, friendID: friend, restaurantID: restaurant, rating: rating,
                   comment: "架空のレビュー", updatedAt: Date(timeIntervalSince1970: time))
    }

    func testLatestRatingByEachFriendCountsOnce() {
        let summary = FriendRatingSummary(restaurantID: "shop", reviews: [
            review("new", rating: 5, time: 2), review("old", rating: 1),
            review("other", friend: "b", rating: 4)
        ])
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.average, 4.5)
        XCTAssertEqual(Set(summary.reviews.map(\.id)), ["new", "other"])
    }

    func testUnreviewedRestaurantHasNoAverage() {
        let summary = FriendRatingSummary(restaurantID: "other", reviews: [review("r", rating: 5)])
        XCTAssertNil(summary.average)
        XCTAssertEqual(summary.count, 0)
    }

    func testInvalidRatingIsNotIncluded() {
        let summary = FriendRatingSummary(restaurantID: "shop", reviews: [
            review("zero", friend: "a", rating: 0), review("fraction", friend: "b", rating: 4.2),
            review("valid", friend: "c", rating: 3.5)
        ])
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.average, 3.5)
    }
}
