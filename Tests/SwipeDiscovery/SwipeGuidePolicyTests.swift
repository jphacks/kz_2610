import XCTest
@testable import meshinowa

final class SwipeGuidePolicyTests: XCTestCase {
    func testInitialThenFiveHintsThenNone() {
        var state = SwipeGuideState.initial
        XCTAssertEqual(SwipeGuidePolicy.mode(for: state), .initial)
        state = SwipeGuidePolicy.afterDecision(state)            // 1枚目で完了
        for _ in 0..<5 {
            XCTAssertEqual(SwipeGuidePolicy.mode(for: state), .hint)   // 2〜6枚目
            state = SwipeGuidePolicy.afterDecision(state)
        }
        XCTAssertEqual(SwipeGuidePolicy.mode(for: state), .none)       // 7枚目から
        XCTAssertEqual(SwipeGuidePolicy.afterDecision(state).hintRemaining, 0)
    }

    func testResetReturnsToInitial() {
        let done = SwipeGuideState(guideCompleted: true, hintRemaining: 0)
        XCTAssertEqual(SwipeGuidePolicy.reset(), .initial)
        XCTAssertNotEqual(done, SwipeGuidePolicy.reset())
    }

    func testArrowOpacities() {
        XCTAssertEqual(SwipeGuidePolicy.arrowOpacities(mode: .hint, dragX: 0).left, 0.4)
        let draggingRight = SwipeGuidePolicy.arrowOpacities(mode: .hint, dragX: 20)
        XCTAssertEqual(draggingRight.right, 1)
        XCTAssertEqual(draggingRight.left, 0.2)
        XCTAssertEqual(SwipeGuidePolicy.arrowOpacities(mode: .none, dragX: 20).right, 0)
    }

    func testStateStoreUsesOwnKeysAndUndoDoesNotRestore() {
        let defaults = UserDefaults(suiteName: "SwipeGuidePolicyTests-\(UUID().uuidString)")!
        let store = SwipeGuideStateStore(defaults: defaults)
        XCTAssertEqual(store.state, .initial)
        store.state = SwipeGuidePolicy.afterDecision(store.state)
        XCTAssertEqual(store.state, SwipeGuideState(guideCompleted: true, hintRemaining: 5))
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("swipeDiscovery.") }.count >= 2)
    }
}
