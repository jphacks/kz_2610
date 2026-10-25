import Foundation

struct BackendConfiguration {
    let url: URL

    var isLoopback: Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host?.lowercased() ?? "")
    }

    /// HTTP over Bonjour is restricted to developer builds on the local network.
    var isDevelopmentHost: Bool {
        if isLoopback { return true }
        #if DEBUG
        return url.host?.lowercased().hasSuffix(".local") == true
        #else
        return false
        #endif
    }

    enum ConfigurationError: LocalizedError {
        case invalidURL
        var errorDescription: String? { "Cloudflare APIのURLが正しくありません。" }
    }

    /// 未設定は端末内モード。アプリに管理キーを埋め込まず、設定値もエラーに含めない。
    static func load(info: [String: Any]) throws -> BackendConfiguration? {
        let raw = (info["CloudflareAPIURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", !raw.contains("REPLACE_ME"),
              !raw.contains("$("), !raw.contains(where: { $0.isWhitespace }),
              url.scheme == "https" || (url.scheme == "http" && BackendConfiguration(url: url).isDevelopmentHost) else {
            throw ConfigurationError.invalidURL
        }
        return BackendConfiguration(url: url)
    }
}
