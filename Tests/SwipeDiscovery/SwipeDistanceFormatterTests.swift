import XCTest
@testable import meshinowa

final class SwipeDistanceFormatterTests: XCTestCase {
    func testLabel() {
        XCTAssertEqual(SwipeDistanceFormatter.label(meters: 650), "650m・徒歩約8分")
        XCTAssertEqual(SwipeDistanceFormatter.label(meters: 640), "640m・徒歩約8分")
        XCTAssertEqual(SwipeDistanceFormatter.label(meters: 3), "10m・徒歩約1分")
        XCTAssertEqual(SwipeDistanceFormatter.label(meters: 1234), "1.2km・徒歩約15分")
        XCTAssertEqual(SwipeDistanceFormatter.distanceText(meters: 12_400), "12km")
    }

    func testAccessibilityLabel() {
        XCTAssertEqual(SwipeDistanceFormatter.accessibilityLabel(meters: 640), "640m、徒歩約8分")
    }

    func testRadiusText() {
        XCTAssertEqual(SwipeDistanceFormatter.radiusText(meters: 500), "500m")
        XCTAssertEqual(SwipeDistanceFormatter.radiusText(meters: 1000), "1km")
        XCTAssertEqual(SwipeDistanceFormatter.radiusText(meters: 3000), "3km")
    }
}
