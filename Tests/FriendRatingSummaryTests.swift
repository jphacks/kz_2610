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
    func testRecommendedMapIncludesRatedShopsWithoutPlaceSearch() {
        XCTAssertEqual(Set(TestRecommendations.dataset.ratedRestaurants.map(\.id)),
                       ["diner", "cafe", "noodles", "bakery"])
    }

    func testRecommendedMapRemovesShopsWhenReviewsOrFriendsDisappear() {
        var dataset = TestRecommendations.dataset
        dataset.reviews = []
        XCTAssertTrue(dataset.ratedRestaurants.isEmpty)
        dataset = TestRecommendations.dataset
        dataset.friends = []
        XCTAssertTrue(dataset.ratedRestaurants.isEmpty)
        dataset = TestRecommendations.dataset
        dataset.reviews = [review("invalid", friend: "takuma", restaurant: "diner", rating: 4.2)]
        XCTAssertTrue(dataset.ratedRestaurants.isEmpty)
    }

    func testMapMergesGeneralShopsAndKeepsFriendShopFirstWithoutDuplicates() {
        let recommended = RestaurantSearchResult(item: TestRecommendations.restaurants[0].mapItem)
        let searchedItem = TestRecommendations.restaurants[0].mapItem
        searchedItem.phoneNumber = "03-0000-0000"
        let general = RestaurantSearchResult(item: TestRecommendations.restaurants[1].mapItem)
        let friendOnly = RestaurantSearchResult(item: TestRecommendations.restaurants[3].mapItem)
        let merged = RestaurantSearchResult.merging(
            search: [general, RestaurantSearchResult(item: searchedItem), general],
            recommendations: [recommended, friendOnly])
        XCTAssertEqual(merged.map(\.id), [recommended.id, friendOnly.id, general.id])
        XCTAssertEqual(merged.first?.item.phoneNumber, searchedItem.phoneNumber)
        XCTAssertEqual(RestaurantSearchResult.merging(search: [], recommendations: [recommended]).first?.id,
                       recommended.id)
    }

    func testFriendPinsHavePriorityOverGeneralAndPersonalPins() {
        let general = RestaurantSearchResult.displayPriority(isSelected: false, hasFriendRating: false, hasPersonalRecord: false)
        let personal = RestaurantSearchResult.displayPriority(isSelected: false, hasFriendRating: false, hasPersonalRecord: true)
        let friend = RestaurantSearchResult.displayPriority(isSelected: false, hasFriendRating: true, hasPersonalRecord: false)
        let selected = RestaurantSearchResult.displayPriority(isSelected: true, hasFriendRating: false, hasPersonalRecord: false)
        XCTAssertGreaterThan(personal, general)
        XCTAssertGreaterThan(friend, personal)
        XCTAssertGreaterThan(selected, friend)
    }

}
