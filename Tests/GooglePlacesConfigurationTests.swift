import XCTest
@testable import meshinowa

final class GooglePlacesConfigurationTests: XCTestCase {
    func testMissingKeyKeepsAppUsableWithoutGoogleRequests() throws {
        XCTAssertNil(try GooglePlacesConfiguration.load(info: [:]))
        XCTAssertNil(try GooglePlacesConfiguration.load(info: ["GooglePlacesAPIKey": "  "]))
    }

    func testIOSKeyFormatAndWhitespace() throws {
        let synthetic = "AIza" + String(repeating: "a", count: 35)
        let configuration = try GooglePlacesConfiguration.load(info: ["GooglePlacesAPIKey": " \(synthetic)\n"])
        XCTAssertEqual(configuration?.apiKey, synthetic)
    }

    func testMisconfiguredOrPrivilegedValuesAreRejectedWithoutEchoingThem() {
        for key in ["$(GOOGLE_PLACES_IOS_API_KEY)", "AIza_REPLACE_ME", "server-secret-fixture", "AIza" + String(repeating: "a", count: 34) + " "] {
            XCTAssertThrowsError(try GooglePlacesConfiguration.load(info: ["GooglePlacesAPIKey": key])) { error in
                XCTAssertFalse(error.localizedDescription.contains(key))
            }
        }
    }
}
