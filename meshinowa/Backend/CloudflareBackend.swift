import Foundation

/// 認証・同期用の接続口。端末内ストアは明示的な呼び出しなしに送信しない。
struct CloudflareBackend {
    let configuration: BackendConfiguration
    var session: URLSession = .shared

    struct AuthChallenge: Decodable {
        let nonce: String
        let nonceHash: String
        let expiresIn: Int
    }

    struct AuthSession: Decodable {
        let accessToken: String
        let expiresAt: Int
        let userId: UUID
    }

    enum BackendError: LocalizedError {
        case invalidPath, invalidSession, invalidResponse, http(Int)
        var errorDescription: String? {
            switch self {
            case .invalidPath: return "APIのパスが正しくありません。"
            case .invalidSession: return "再度ログインしてください。"
            case .invalidResponse: return "サーバーの応答を読み込めませんでした。"
            case .http(let status): return "サーバーへの接続に失敗しました（\(status)）。"
            }
        }
    }

    static func makeClient(bundle: Bundle = .main) throws -> CloudflareBackend? {
        guard let configuration = try BackendConfiguration.load(info: bundle.infoDictionary ?? [:]) else { return nil }
        return CloudflareBackend(configuration: configuration)
    }

    func authChallenge() async throws -> AuthChallenge {
        try await request("/auth/challenge", method: "POST")
    }

    /// Apple認証リクエストのnonceには、challenge.nonceHashを設定する。
    /// 返されたセッションは呼び出し側でKeychainに保存し、UserDefaultsやログへ出さない。
    func signInWithApple(identityToken: String, nonce: String) async throws -> AuthSession {
        let payload = try JSONEncoder().encode(["identity_token": identityToken, "nonce": nonce])
        return try await request("/auth/apple", method: "POST", body: payload)
    }

    func signOut(accessToken: String) async throws {
        _ = try await data("/auth/session", method: "DELETE", accessToken: accessToken)
    }

    func request<T: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [],
                               accessToken: String? = nil, body: Data? = nil) async throws -> T {
        let response = try await data(path, method: method, query: query, accessToken: accessToken, body: body)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: response) }
        catch { throw BackendError.invalidResponse }
    }

    /// 写真はReviewPhotoCodecでメタデータを除去したJPEGを渡す。
    /// URLや認証ヘッダーをログに出さず、リダイレクト先へセッションを送らない。
    func data(_ path: String, method: String = "GET", query: [URLQueryItem] = [], accessToken: String? = nil,
              body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains(".."),
              !path.contains("?"), !path.contains("#"), !path.contains("%"), !path.contains("\\"),
              var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: false) else {
            throw BackendError.invalidPath
        }
        components.path = "/v1" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw BackendError.invalidPath }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.setValue(contentType, forHTTPHeaderField: "Content-Type"); request.httpBody = body }
        if let accessToken {
            guard accessToken.count == 64, accessToken.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                throw BackendError.invalidSession
            }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
        guard let response = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw BackendError.http(response.statusCode) }
        return data
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
