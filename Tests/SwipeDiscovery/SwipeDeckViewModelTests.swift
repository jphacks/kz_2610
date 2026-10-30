import XCTest
@testable import meshinowa

/// 右スワイプ→行きたいに入る、戻す→行きたいから消える、保存失敗→判断が記録されない（v5）。
@MainActor
final class SwipeDeckViewModelTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SwipeDeckViewModelTests-\(UUID().uuidString)")
    }

    private func makeViewModel(bridge: MockSavedShopsBridge, url: URL = SwipeFixtures.temporaryURL(),
                               candidates: [SwipeCandidate]? = nil) -> SwipeDeckViewModel {
        let provider = MockFriendReviewProvider(result: .success(candidates ?? ["a", "b"].map { SwipeFixtures.candidate($0) }))
        return SwipeDeckViewModel(dependencies: .test(provider: provider, bridge: bridge, storeURL: url, defaults: defaults))
    }

    func testRightSwipeSavesToWantToGoAndUndoRemovesIt() async {
        let bridge = MockSavedShopsBridge()
        let viewModel = makeViewModel(bridge: bridge)
        await viewModel.reload()
        XCTAssertEqual(viewModel.phase, .ready)
        let succeeded = await viewModel.decide(.interested)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(bridge.wantToGo, ["a"])
        XCTAssertEqual(viewModel.notice, "行きたいに保存しました")
        XCTAssertEqual(viewModel.deck.top?.id, "b")

        await viewModel.undo()
        XCTAssertTrue(bridge.wantToGo.isEmpty)
        XCTAssertEqual(viewModel.deck.top?.id, "a")
        XCTAssertTrue(viewModel.decisions.isEmpty)
    }

    func testSaveFailureKeepsCardAndRecordsNothing() async {
        let bridge = MockSavedShopsBridge()
        bridge.failsToAdd = true
        let url = SwipeFixtures.temporaryURL()
        let viewModel = makeViewModel(bridge: bridge, url: url)
        await viewModel.reload()
        let succeeded = await viewModel.decide(.interested)
        XCTAssertFalse(succeeded)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.deck.top?.id, "a")
        XCTAssertTrue(viewModel.decisions.isEmpty)
        let stored = await SwipeDecisionStore(fileURL: url).load()
        XCTAssertTrue(stored.isEmpty)
    }

    func testRemovedFromWantToGoReturnsToDeck() async {
        let bridge = MockSavedShopsBridge()
        let viewModel = makeViewModel(bridge: bridge)
        await viewModel.reload()
        await viewModel.decide(.interested)
        // 既存の保存画面などで行きたいから外された。
        bridge.wantToGo.removeAll()
        await viewModel.reload()
        XCTAssertEqual(viewModel.deck.queue.map(\.id), ["a", "b"])
    }

    func testVisitedShopStaysOutOfDeck() async {
        let bridge = MockSavedShopsBridge()
        let viewModel = makeViewModel(bridge: bridge)
        await viewModel.reload()
        await viewModel.decide(.interested)
        // 行きたい → 行った（レビュー済み）に移った。
        bridge.wantToGo.removeAll()
        bridge.visited = ["a"]
        await viewModel.reload()
        XCTAssertEqual(viewModel.deck.queue.map(\.id), ["b"])
    }

    func testFinishedAndEmptyStates() async {
        let bridge = MockSavedShopsBridge()
        let viewModel = makeViewModel(bridge: bridge, candidates: [SwipeFixtures.candidate("a")])
        await viewModel.reload()
        await viewModel.decide(.notInterested)
        XCTAssertEqual(viewModel.phase, .finished)
        XCTAssertTrue(viewModel.hasActiveNotInterested)
        await viewModel.resetNotInterested()
        XCTAssertEqual(viewModel.deck.top?.id, "a")

        let empty = makeViewModel(bridge: MockSavedShopsBridge(), candidates: [SwipeFixtures.candidate("far", metersNorth: 5000)])
        await empty.reload()
        XCTAssertEqual(empty.phase, .empty)
        XCTAssertTrue(empty.usesDefaultArea)
    }

    func testRadiusExpandsUpTo50km() async {
        let viewModel = makeViewModel(bridge: MockSavedShopsBridge(), candidates: [SwipeFixtures.candidate("far", metersNorth: 40_000)])
        await viewModel.apply(radius: 30_000, category: nil, lens: .all)
        XCTAssertEqual(viewModel.phase, .empty)
        XCTAssertTrue(viewModel.canExpandRadius)

        await viewModel.expandRadius()
        XCTAssertEqual(viewModel.radius, 50_000)
        XCTAssertEqual(viewModel.deck.top?.id, "far")
        XCTAssertFalse(viewModel.canExpandRadius)
    }

    func testGuideCompletesOnFirstDecisionAndUndoDoesNotRestoreIt() async {
        let viewModel = makeViewModel(bridge: MockSavedShopsBridge())
        await viewModel.reload()
        XCTAssertEqual(viewModel.guideMode, .initial)
        await viewModel.decide(.notInterested)
        XCTAssertEqual(viewModel.guideMode, .hint)
        await viewModel.undo()
        XCTAssertEqual(viewModel.guideMode, .hint)
        viewModel.resetGuide()
        XCTAssertEqual(viewModel.guideMode, .initial)
    }

    func testCurrentLocationFailureShowsMessageAndKeepsDefaultArea() async {
        let viewModel = makeViewModel(bridge: MockSavedShopsBridge())
        await viewModel.reload()
        await viewModel.useCurrentLocation()
        XCTAssertEqual(viewModel.errorMessage, "位置情報を使えません（テスト）")
        XCTAssertTrue(viewModel.usesDefaultArea)
        XCTAssertFalse(viewModel.isLocating)
    }
}
