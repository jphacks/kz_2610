import Network
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

    func testLoopbackAPIUsesRealHTTP() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        defer { listener.cancel() }
        let ready = expectation(description: "local fixture ready")
        let queue = DispatchQueue(label: "meshinowa.tests.loopback")
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.fulfill()
            case .failed: XCTFail("Local fixture failed to start"); ready.fulfill()
            default: break
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { _, _, _, _ in
                let body = "{\"error\":\"temporarily_unavailable\"}"
                let response = "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(listener.port)
        let backend = CloudflareBackend(configuration: BackendConfiguration(url: URL(string: "http://127.0.0.1:\(port.rawValue)")!),
                                         session: URLSession(configuration: .ephemeral))
        do {
            _ = try await backend.data("/health")
            XCTFail("Expected fixture's HTTP 503")
        } catch CloudflareBackend.BackendError.http(let status) {
            XCTAssertEqual(status, 503)
        }
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
