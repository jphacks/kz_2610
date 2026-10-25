import XCTest
@testable import meshinowa

final class CloudflareBackendTests: XCTestCase {
    private func client() -> CloudflareBackend {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendURLProtocol.self]
        return CloudflareBackend(configuration: BackendConfiguration(url: URL(string: "https://api.example.test")!),
                                 session: URLSession(configuration: config))
    }

    override func tearDown() {
        BackendURLProtocol.handler = nil
        super.tearDown()
    }

    func testChallengeAndAuthenticatedRequestUseVersionedAPI() async throws {
        BackendURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/challenge")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data("{\"nonce\":\"fixture\",\"nonce_hash\":\"hash\",\"expires_in\":600}".utf8))
        }
        let backend = client()
        let challenge = try await backend.authChallenge()
        XCTAssertEqual(challenge.expiresIn, 600)
        XCTAssertEqual(challenge.nonceHash, "hash")
        BackendURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/me")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "a", count: 64))
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return (200, Data("{}".utf8))
        }
        _ = try await backend.data("/me", accessToken: String(repeating: "a", count: 64))
    }

    func testInvalidPathsAndTokensFailBeforeSending() async {
        BackendURLProtocol.handler = { _ in XCTFail("Must not send invalid request"); return (200, Data()) }
        let backend = client()
        for path in ["https://other.example.test", "//other.example.test", "/../me", "/me?token=fixture", "/%2e%2e/me", "/me#fragment"] {
            do { _ = try await backend.data(path); XCTFail("Expected invalid path") }
            catch { XCTAssertTrue(error is CloudflareBackend.BackendError) }
        }
        do { _ = try await backend.data("/me", accessToken: "invalid\r\nheader"); XCTFail("Expected invalid token") }
        catch { XCTAssertTrue(error is CloudflareBackend.BackendError) }
    }

    func testServerResponseAndDecodeErrorsDoNotExposeSensitiveBody() async {
        let backend = client()
        BackendURLProtocol.handler = { _ in (401, Data("sensitive fixture response".utf8)) }
        do { _ = try await backend.data("/me"); XCTFail("Expected HTTP error") }
        catch { XCTAssertFalse(error.localizedDescription.contains("sensitive")) }
        BackendURLProtocol.handler = { _ in (200, Data("invalid sensitive response".utf8)) }
        do { let _: CloudflareBackend.AuthChallenge = try await backend.request("/auth/challenge"); XCTFail("Expected decode error") }
        catch { XCTAssertFalse(error.localizedDescription.contains("sensitive")) }
    }
}

private final class BackendURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
