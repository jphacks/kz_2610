import XCTest
@testable import meshinowa

final class SwipeDecisionReconcilerTests: XCTestCase {
    private let decidedAt: TimeInterval = 1_000_000

    private func reconcile(_ decisions: [SwipeDecision], after seconds: TimeInterval,
                           excluded: Set<String> = []) -> SwipeDecisionReconciler.Result {
        SwipeDecisionReconciler.reconcile(decisions, now: Date(timeIntervalSince1970: decidedAt + seconds),
                                          isExcluded: { excluded.contains($0) })
    }

    func testNotInterestedStaysUntil23h59m() {
        let decision = SwipeFixtures.decision("a", kind: .notInterested, at: decidedAt)
        let result = reconcile([decision], after: 23 * 3600 + 59 * 60)
        XCTAssertEqual(result.kept.map(\.id), ["a"])
        XCTAssertTrue(result.removed.isEmpty)
    }

    func testNotInterestedIsRemovedAtExactly24Hours() {
        let decision = SwipeFixtures.decision("a", kind: .notInterested, at: decidedAt)
        XCTAssertEqual(reconcile([decision], after: 86_400).removed.map(\.id), ["a"])
    }

    func testClockMovingBackwardsDoesNotRemove() {
        let decision = SwipeFixtures.decision("a", kind: .notInterested, at: decidedAt)
        XCTAssertEqual(reconcile([decision], after: -5 * 86_400).kept.map(\.id), ["a"])
    }

    func testInterestedStaysWhileInWantToGoOrVisited() {
        let decision = SwipeFixtures.decision("a", kind: .interested, at: decidedAt)
        // 行きたい → 行った（レビュー済み）に移っても残る（デッキに出さない）。
        XCTAssertEqual(reconcile([decision], after: 10 * 86_400, excluded: ["a"]).kept.map(\.id), ["a"])
    }

    func testInterestedIsRemovedWhenNoLongerSaved() {
        let decision = SwipeFixtures.decision("a", kind: .interested, at: decidedAt)
        XCTAssertEqual(reconcile([decision], after: 60, excluded: []).removed.map(\.id), ["a"])
    }

    func testHoursUntilReturnRoundsUp() {
        let decision = SwipeFixtures.decision("a", kind: .notInterested, at: decidedAt)
        let now = Date(timeIntervalSince1970: decidedAt + 3600 + 1)
        XCTAssertEqual(SwipeDecisionReconciler.hoursUntilReturn(decision, now: now), 23)
        XCTAssertTrue(SwipeDecisionReconciler.hasActiveNotInterested([decision], now: now))
        XCTAssertFalse(SwipeDecisionReconciler.hasActiveNotInterested(
            [decision], now: Date(timeIntervalSince1970: decidedAt + 86_400)))
    }
}
