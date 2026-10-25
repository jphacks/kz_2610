import Foundation

/// 「行きたい」を Cloudflare（D1 の want_to_go テーブル）に同期する。
/// 既存の CloudflareBackend と、FriendStore が Keychain に保存したゲストのトークンを読むだけで使う。
/// トークンがまだない（ゲスト作成前）時は送らず、端末に残して次の同期を待つ。
struct CloudflareWantToGoRemote: SwipeWantToGoRemote {
    enum RemoteError: Error { case notSignedIn }

    private let backend: CloudflareBackend
    private let credentials: GuestCredentialStore

    init(backend: CloudflareBackend, credentials: GuestCredentialStore = GuestCredentialStore()) {
        self.backend = backend
        self.credentials = credentials
    }

    /// Cloudflare が未設定なら nil（端末内だけで使う）。
    static func makeDefault() -> CloudflareWantToGoRemote? {
        guard let backend = try? CloudflareBackend.makeClient() else { return nil }
        return CloudflareWantToGoRemote(backend: backend)
    }

    func add(_ entry: SwipeWantToGoEntry) async throws -> String {
        let token = try accessToken()
        let restaurantID = try await restaurantID(for: entry, token: token)
        let _: [String: Bool] = try await backend.request("/want-to-go/\(restaurantID)", method: "PUT", accessToken: token)
        return restaurantID
    }

    func remove(_ entry: SwipeWantToGoEntry) async throws {
        let token = try accessToken()
        let restaurantID: String
        if let known = entry.remoteRestaurantID { restaurantID = known } else {
            restaurantID = try await self.restaurantID(for: entry, token: token)
        }
        let _: [String: Bool] = try await backend.request("/want-to-go/\(restaurantID)", method: "DELETE", accessToken: token)
    }

    func list() async throws -> [SwipeWantToGoRemoteItem] {
        struct Row: Decodable {
            let restaurantId: String
            let externalKey: String
            let name: String
            let category: String?
            let address: String?
            let latitude: Double
            let longitude: Double
            let addedAt: String
        }
        let rows: [Row] = try await backend.request("/want-to-go", accessToken: try accessToken())
        return rows.map {
            SwipeWantToGoRemoteItem(restaurantID: $0.restaurantId, externalKey: $0.externalKey, name: $0.name,
                                    category: $0.category, address: $0.address,
                                    latitude: $0.latitude, longitude: $0.longitude, addedAt: Self.date($0.addedAt))
        }
    }

    private func accessToken() throws -> String {
        guard let token = credentials.load() else { throw RemoteError.notSignedIn }
        return token
    }

    /// 既存のレビュー共有と同じく、店名＋座標の店舗IDを external_key にして店舗を作る（既にあれば同じIDが返る）。
    private func restaurantID(for entry: SwipeWantToGoEntry, token: String) async throws -> String {
        struct Created: Decodable { let id: String }
        var body: [String: Any] = [
            "external_key": String(entry.id.prefix(300)), "name": String(entry.name.prefix(200)),
            "latitude": entry.latitude, "longitude": entry.longitude,
            "address": String((entry.address ?? "").prefix(500))
        ]
        // category は他の画面が MapKit のカテゴリ値として読むので、その形式の時だけ送る。
        if let genre = entry.genre, genre.hasPrefix("MKPOICategory") { body["category"] = String(genre.prefix(100)) }
        // Place ID 形式の店舗IDなら、サーバーの店舗とも Place ID で照合する。
        if entry.id.hasPrefix("google:") { body["google_place_id"] = String(entry.id.dropFirst("google:".count).prefix(300)) }
        let data = try JSONSerialization.data(withJSONObject: body)
        let created: Created = try await backend.request("/restaurants", method: "POST", accessToken: token, body: data)
        return created.id
    }

    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? .now
    }
}
