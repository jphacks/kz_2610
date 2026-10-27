import XCTest
@testable import meshinowa

final class FriendLensTests: XCTestCase {
    private let friends = TestRecommendations.friends
    private let favorites = TestRecommendations.favoriteFriendIDs

    func testNewFriendMapContainsOnlyThatFriendsRatedRestaurants() {
        let scoped = TestRecommendations.dataset.forFriend("mio")
        XCTAssertEqual(scoped.friends.map(\.id), ["mio"])
        XCTAssertEqual(scoped.favoriteFriendIDs, ["mio"])
        XCTAssertEqual(Set(scoped.reviews.map(\.friendID)), ["mio"])
        XCTAssertEqual(Set(scoped.restaurants.map(\.id)), ["cafe", "bakery"])
        XCTAssertEqual(scoped.summary(for: scoped.restaurants[0]).count, 1)
        let missing = TestRecommendations.dataset.forFriend("unknown")
        XCTAssertTrue(missing.friends.isEmpty)
        XCTAssertTrue(missing.restaurants.isEmpty)
        XCTAssertTrue(missing.reviews.isEmpty)
        var noReviews = TestRecommendations.dataset
        noReviews.reviews = []
        XCTAssertTrue(noReviews.forFriend("mio").restaurants.isEmpty)
    }

    func testSelectedFriendUsesOnlyTheirLatestReview() throws {
        let shop = try XCTUnwrap(TestRecommendations.restaurants.first { $0.id == "diner" })
        let lens = FriendLens(mode: .selectedFriends, selectedFriendIDs: ["takuma"])
        let ids = lens.includedFriendIDs(friends: friends, favorites: favorites)
        let summary = TestRecommendations.summary(for: shop, friendIDs: ids)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.average, 5)
        XCTAssertEqual(summary.reviews.map(\.friendID), ["takuma"])
    }

    func testEmptySelectionAndUnreviewedFriendHaveNoAverage() throws {
        let shop = try XCTUnwrap(TestRecommendations.restaurants.first { $0.id == "diner" })
        for ids: Set<String> in [[], ["saki"]] {
            let summary = TestRecommendations.summary(for: shop, friendIDs: ids)
            XCTAssertNil(summary.average)
            XCTAssertEqual(summary.count, 0)
        }
    }

    func testFavoritesAndSelectedIDsExcludeUnknownFriends() {
        let selected = FriendLens(mode: .selectedFriends, selectedFriendIDs: ["mio", "unknown"])
        XCTAssertEqual(selected.includedFriendIDs(friends: friends, favorites: favorites), ["mio"])
        let favoriteLens = FriendLens(mode: .favoriteFriends)
        XCTAssertEqual(favoriteLens.includedFriendIDs(friends: friends, favorites: favorites.union(["unknown"])), favorites)
    }

    func testSwitchingBackToAllFriendsRestoresRatings() throws {
        let shop = try XCTUnwrap(TestRecommendations.restaurants.first { $0.id == "diner" })
        var lens = FriendLens(mode: .selectedFriends, selectedFriendIDs: ["takuma"])
        lens.mode = .allFriends
        let summary = TestRecommendations.summary(for: shop, friendIDs: lens.includedFriendIDs(friends: friends, favorites: favorites))
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(try XCTUnwrap(summary.average), 14.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(lens.selectedFriendIDs, ["takuma"])
    }
}
