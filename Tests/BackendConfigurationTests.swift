import XCTest
@testable import meshinowa

final class BackendConfigurationTests: XCTestCase {
    func testMissingConfigurationKeepsLocalMode() throws {
        XCTAssertNil(try BackendConfiguration.load(info: [:]))
        XCTAssertNil(try BackendConfiguration.load(info: ["CloudflareAPIURL": "  "]))
    }
    func testCloudflareAndLoopbackOriginsNeedNoEmbeddedKey() throws {
        let cloud = try BackendConfiguration.load(info: ["CloudflareAPIURL": "https://api.example.test"])
        XCTAssertEqual(cloud?.url.host, "api.example.test")
        for url in ["http://localhost:8787", "http://127.0.0.1:8787", "http://[::1]:8787"] {
            XCTAssertNotNil(try BackendConfiguration.load(info: ["CloudflareAPIURL": url]))
        }
    }
    func testInsecureCredentialBearingAndPlaceholderURLsAreRejected() {
        for url in ["http://example.com", "https://user:password@example.com", "https://example.com?key=value", "https://example.com/v1", "https://example.com#token", "$(CLOUDFLARE_API_URL)", "https://REPLACE_ME.workers.dev"] {
            XCTAssertThrowsError(try BackendConfiguration.load(info: ["CloudflareAPIURL": url]))
        }
    }
}
