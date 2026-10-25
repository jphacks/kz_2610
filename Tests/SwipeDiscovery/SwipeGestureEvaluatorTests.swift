import XCTest
@testable import meshinowa

final class SwipeGestureEvaluatorTests: XCTestCase {
    private let regions = SwipeCardRegions(size: CGSize(width: 300, height: 500),
                                           locationInset: CGRect(x: 200, y: 12, width: 88, height: 110),
                                           infoArea: CGRect(x: 0, y: 400, width: 300, height: 100),
                                           showsPhotos: true)

    private func release(distance: CGFloat = 0, duration: TimeInterval = 0.1, x: CGFloat = 0, predicted: CGFloat? = nil,
                         at location: CGPoint = CGPoint(x: 50, y: 200)) -> SwipeReleaseOutcome {
        SwipeGestureEvaluator.evaluateRelease(maxDistance: distance, duration: duration,
                                              translation: CGSize(width: x, height: 0),
                                              predictedEndTranslation: CGSize(width: predicted ?? x, height: 0),
                                              location: location, regions: regions)
    }

    // MARK: タップとドラッグの境目（5pt・0.3秒）

    func testShortTouchUnderFivePointsIsTap() {
        XCTAssertEqual(release(distance: 4.9, duration: 0.29), .tap(.previousPhoto))
    }

    func testFivePointsIsDrag() {
        XCTAssertEqual(release(distance: 5, duration: 0.1, x: 5), .cancel)
    }

    func testLongPressUnderFivePointsDoesNothing() {
        XCTAssertEqual(release(distance: 2, duration: 0.3), .longPress)
    }

    // MARK: タップの振り分け

    func testTapTargets() {
        XCTAssertEqual(release(at: CGPoint(x: 50, y: 200)), .tap(.previousPhoto))
        XCTAssertEqual(release(at: CGPoint(x: 160, y: 200)), .tap(.nextPhoto))
        XCTAssertEqual(release(at: CGPoint(x: 240, y: 50)), .tap(.map))
        XCTAssertEqual(release(at: CGPoint(x: 100, y: 450)), .tap(.detail))
    }

    func testRatingHeroSideTapDoesNothing() {
        var hero = regions
        hero.showsPhotos = false
        XCTAssertEqual(SwipeGestureEvaluator.tapTarget(at: CGPoint(x: 50, y: 200), regions: hero), .none)
        XCTAssertEqual(SwipeGestureEvaluator.tapTarget(at: CGPoint(x: 100, y: 450), regions: hero), .detail)
    }

    // MARK: 確定しきい値

    func testDistanceThreshold() {
        XCTAssertEqual(release(distance: 106, x: 106), .commit(.interested))   // 35% of 300 = 105
        XCTAssertEqual(release(distance: 104, x: -104), .cancel)
        XCTAssertEqual(release(distance: 106, x: -106), .commit(.notInterested))
    }

    func testVelocityThreshold() {
        XCTAssertEqual(release(distance: 40, x: 40, predicted: 181), .commit(.interested))   // 60% of 300 = 180
        XCTAssertEqual(release(distance: 40, x: 40, predicted: 178), .cancel)
        // 指を動かした向きと逆に投げても確定しない。
        XCTAssertEqual(release(distance: 40, x: 40, predicted: -200), .cancel)
    }

    func testRotationAndOverlayAreClamped() {
        XCTAssertEqual(SwipeGestureEvaluator.rotationDegrees(translationX: 1000, cardWidth: 300), 15)
        XCTAssertEqual(SwipeGestureEvaluator.rotationDegrees(translationX: -1000, cardWidth: 300), -15)
        XCTAssertEqual(SwipeGestureEvaluator.overlayOpacity(translationX: 0, cardWidth: 300), 0)
        XCTAssertEqual(SwipeGestureEvaluator.overlayOpacity(translationX: 400, cardWidth: 300), 0.85, accuracy: 0.0001)
    }
}
