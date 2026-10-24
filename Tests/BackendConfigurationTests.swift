import XCTest
@testable import meshinowa

final class BackendConfigurationTests: XCTestCase {
    private let key = "sb_publishable_test_fixture_not_a_real_key"

    func testMissingConfigurationKeepsLocalMode() throws {
        XCTAssertNil(try BackendConfiguration.load(info: [:]))
    }
    func testPublishableConfigurationAndLocalDevelopment() throws {
        let cloud = try BackendConfiguration.load(info: ["SupabaseURL": "https://example.supabase.co", "SupabasePublishableKey": key])
        XCTAssertEqual(cloud?.url.host, "example.supabase.co")
        XCTAssertNotNil(try BackendConfiguration.load(info: ["SupabaseURL": "http://127.0.0.1:54321", "SupabasePublishableKey": key]))
    }
    func testPrivilegedAndLegacyKeysAreRejected() {
        for value in ["sb_secret_test_only", "eyJhbGciOiJIUzI1NiJ9.test.signature", "sb_publishable_REPLACE_ME"] {
            XCTAssertThrowsError(try BackendConfiguration.load(info: ["SupabaseURL": "https://example.supabase.co", "SupabasePublishableKey": value]))
        }
    }
    func testInsecureAndCredentialBearingURLsAreRejected() {
        for url in ["http://example.com", "https://user:password@example.com", "https://example.com?key=value", "https://example.com/rest/v1"] {
            XCTAssertThrowsError(try BackendConfiguration.load(info: ["SupabaseURL": url, "SupabasePublishableKey": key]))
        }
    }
}
