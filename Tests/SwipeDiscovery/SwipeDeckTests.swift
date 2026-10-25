import XCTest
@testable import meshinowa

final class SwipeDeckTests: XCTestCase {
    func testDuplicatesAreRemovedAndOrderKept() {
        let deck = SwipeDeck(candidates: [SwipeFixtures.candidate("a"), SwipeFixtures.candidate("b"),
                                          SwipeFixtures.candidate("a")])
        XCTAssertEqual(deck.queue.map(\.id), ["a", "b"])
        XCTAssertEqual(deck.visible().map(\.id), ["a", "b"])
    }

    func testDecideAndUndoRestoresSameCardOnTop() {
        var deck = SwipeDeck(candidates: ["a", "b", "c"].map { SwipeFixtures.candidate($0) })
        XCTAssertFalse(deck.canUndo)
        deck.decide(.interested, at: Date(timeIntervalSince1970: 1))
        deck.decide(.notInterested, at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(deck.top?.id, "c")
        XCTAssertEqual(deck.undo()?.id, "b")
        XCTAssertEqual(deck.top?.id, "b")
        XCTAssertEqual(deck.undo()?.kind, .interested)
        XCTAssertEqual(deck.queue.map(\.id), ["a", "b", "c"])
        XCTAssertNil(deck.undo())
    }

    func testVisibleShowsAtMostThreeCards() {
        let deck = SwipeDeck(candidates: (0..<5).map { SwipeFixtures.candidate("\($0)") })
        XCTAssertEqual(deck.visible().count, 3)
    }

    func testReplaceQueueKeepsHistoryAndSkipsDecided() {
        var deck = SwipeDeck(candidates: ["a", "b"].map { SwipeFixtures.candidate($0) })
        deck.decide(.interested, at: .now)
        deck.replaceQueue(with: ["a", "b", "c"].map { SwipeFixtures.candidate($0) })
        XCTAssertEqual(deck.queue.map(\.id), ["b", "c"])
        XCTAssertTrue(deck.canUndo)
    }

    func testForgetRemovesReconciledDecisionsFromUndo() {
        var deck = SwipeDeck(candidates: ["a"].map { SwipeFixtures.candidate($0) })
        deck.decide(.notInterested, at: .now)
        deck.forget(ids: ["a"])
        XCTAssertFalse(deck.canUndo)
    }
}
