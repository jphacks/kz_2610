import XCTest
@testable import meshinowa

final class InviteLinkTests: XCTestCase {
    func testOnlyValidTokensAndTrustedOriginsAreAccepted() throws {
        let token = String(repeating: "a", count: 64)
        let origin = URL(string: "https://invite.example.test")!
        XCTAssertEqual(InviteLink.token(from: URL(string: "meshinowa://invite/\(token)")!, backendURL: nil), token)
        XCTAssertEqual(InviteLink.token(from: origin.appendingPathComponent("i/\(token)"), backendURL: origin), token)
        for raw in ["https://evil.example.test/i/\(token)", "https://invite.example.test/i/short",
                    "https://invite.example.test/i/\(token)?redirect=evil", "meshinowa://invite/../\(token)",
                    "http://invite.example.test/i/\(token)"] {
            XCTAssertNil(InviteLink.token(from: URL(string: raw)!, backendURL: origin))
        }
    }
}
