import Foundation

struct BackendConfiguration {
    let url: URL
    let publishableKey: String

    enum ConfigurationError: LocalizedError {
        case incomplete, invalidURL, invalidKey
        var errorDescription: String? {
            switch self {
            case .incomplete: return "SupabaseのURLと公開用キーを両方設定してください。"
            case .invalidURL: return "SupabaseのURLが正しくありません。"
            case .invalidKey: return "アプリにはsb_publishable_で始まる公開用キーだけを設定してください。"
            }
        }
    }

    /// 未設定は端末内モード。エラー文に設定値を含めない。
    static func load(info: [String: Any]) throws -> BackendConfiguration? {
        let rawURL = (info["SupabaseURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (info["SupabasePublishableKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if rawURL.isEmpty && key.isEmpty { return nil }
        guard !rawURL.isEmpty, !key.isEmpty else { throw ConfigurationError.incomplete }
        guard let url = URL(string: rawURL), let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", !rawURL.contains("YOUR_PROJECT_REF"),
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else {
            throw ConfigurationError.invalidURL
        }
        guard key.hasPrefix("sb_publishable_"), key.count > 20,
              !key.contains("REPLACE_ME"), !key.contains(where: { $0.isWhitespace }) else {
            throw ConfigurationError.invalidKey
        }
        return BackendConfiguration(url: url, publishableKey: key)
    }
}
