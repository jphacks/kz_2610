import Combine
import Foundation
import MapKit

/// ゲストアカウントと友達のつながり・評価。Cloudflare未設定なら何も送らず、画面はデモを出す。
@MainActor
final class FriendStore: ObservableObject {
    struct Profile: Decodable, Equatable {
        let id: String
        let displayName: String
        let handle: String
        var bio: String?
        var avatarSymbol: String?
    }

    struct Friend: Decodable, Identifiable {
        let id: String
        let displayName: String
        let handle: String
        let bio: String?
        let avatarSymbol: String?
        let isFavorite: Int
    }

    struct Request: Decodable, Identifiable {
        let id: String
        let fromId: String
        let toId: String
        let status: String
        let fromName: String
        let fromHandle: String
        let toName: String
        let toHandle: String
    }

    struct RemoteReview: Decodable, Identifiable {
        let id: String
        let userId: String
        let displayName: String
        let rating: Double
        let comment: String
        let dish: String
        let updatedAt: String
        let googlePlaceId: String?
        let externalKey: String
        let name: String
        let category: String?
        let address: String
        let latitude: Double
        let longitude: Double
    }

    struct Preferences: Decodable {
        var allowIdSearch: Int
        var showVisitDate: Int
        var includeInFriendAvg: Int
    }
    struct BlockedProfile: Decodable, Identifiable {
        let blockedId: String
        let displayName: String?
        var id: String { blockedId }
    }

    enum Status: Equatable { case unavailable, connecting, ready, failed(String) }

    @Published private(set) var status: Status
    @Published private(set) var me: Profile?
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var requests: [Request] = []
    @Published private(set) var friendReviews: [RemoteReview] = []

    @Published private(set) var needsLocalReset = UserDefaults.standard.bool(forKey: "account.needsLocalReset")
    @Published var actionError: String?
    @Published private(set) var syncError: String?
    @Published private(set) var preferences: Preferences?
    @Published private(set) var blockedProfiles: [BlockedProfile] = []
    private var tokenTask: Task<String, Error>?
    private var localRecoveryTask: Task<String, Error>?
    private let environmentStore: UserDefaults
    private var recordedLocalEnvironment = false
    private struct LocalEnvironment: Decodable {
        let instanceId: String
        let isEmpty: Bool
    }
    var suspendsReviewSync = false
    var currentCredential: String? { token ?? credentials.load() }
    private var identityGeneration = 0
    private var refreshSequence = 0
    private var flushing = false
    private var libraryStore: LocalReviewStore?

    private let backend: CloudflareBackend?
    private let credentials: any GuestCredentials
    private var token: String?

    init(backend: CloudflareBackend? = try? CloudflareBackend.makeClient(),
         credentials: any GuestCredentials = GuestCredentialStore(),
         environmentStore: UserDefaults = .standard) {
        self.backend = backend
        self.credentials = credentials
        self.environmentStore = environmentStore
        status = backend == nil ? .unavailable : .connecting
    }

    var isAvailable: Bool { backend != nil }
    var incomingRequests: [Request] { requests.filter { $0.status == "pending" && $0.toId == me?.id } }
    var outgoingRequests: [Request] { requests.filter { $0.status == "pending" && $0.fromId == me?.id } }

    var dataset: FriendDataset {
        var restaurants: [String: FriendRestaurant] = [:]
        for review in friendReviews where restaurants[review.externalKey] == nil {
            let category = MKMapItem()
            category.pointOfInterestCategory = review.category.map(MKPointOfInterestCategory.init(rawValue:))
            restaurants[review.externalKey] = FriendRestaurant(
                id: review.externalKey, name: review.name, genre: category.restaurantCategory,
                coordinate: CLLocationCoordinate2D(latitude: review.latitude, longitude: review.longitude),
                address: review.address, category: review.category, googlePlaceID: review.googlePlaceId)
        }
        return FriendDataset(
            friends: friends.map { FriendProfile(id: $0.id, name: $0.displayName, bio: $0.bio ?? "", avatarSymbol: $0.avatarSymbol ?? "person.fill") },
            favoriteFriendIDs: Set(friends.filter { $0.isFavorite != 0 }.map(\.id)),
            restaurants: restaurants.values.sorted { $0.name < $1.name },
            reviews: friendReviews.map {
                FriendReview(id: $0.id, friendID: $0.userId, restaurantID: $0.externalKey, rating: $0.rating,
                             comment: $0.comment, updatedAt: Self.date($0.updatedAt), dish: $0.dish)
            },
            isDemo: false)
    }

    /// 地図検索のお店に付いた友達の評価。照合キーは保存・レビューと同じ店名＋座標。
    func summary(for item: MKMapItem, friendIDs: Set<String>? = nil) -> FriendRatingSummary {
        let matching = Set(friendReviews.filter {
            if let left = $0.googlePlaceId, let right = item.googleDetails?.placeID { return left == right }
            return $0.externalKey == SavedRestaurant.identifier(for: item)
                || $0.externalKey == SavedRestaurant.legacyIdentifier(for: item)
                || SavedRestaurant.legacyIdentifier(for: mapItem($0)) == SavedRestaurant.legacyIdentifier(for: item)
        }.map(\.externalKey))
        let key = SavedRestaurant.identifier(for: item)
        let matched = dataset.reviews.filter { matching.contains($0.restaurantID) }.map {
            FriendReview(id: $0.id, friendID: $0.friendID, restaurantID: key, rating: $0.rating,
                         comment: $0.comment, updatedAt: $0.updatedAt, dish: $0.dish)
        }
        return FriendRatingSummary(restaurantID: key, reviews: matched, friendIDs: friendIDs)
    }

    private func mapItem(_ review: RemoteReview) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: review.latitude, longitude: review.longitude)))
        item.name = review.name
        return item
    }

    func connect(to reviews: LocalReviewStore) { libraryStore = reviews }

    func pauseReviewSync() async {
        suspendsReviewSync = true
        while flushing { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func flushReviews() async {
        guard isAvailable, !suspendsReviewSync, let libraryStore, !flushing else { return }
        flushing = true
        defer { flushing = false }
        while !suspendsReviewSync, let operation = libraryStore.pending.first {
            do {
                if let review = operation.review { try await upload(review) }
                else { try await removeReview(for: operation.restaurant) }
                try libraryStore.acknowledge(operation)
                syncError = nil
            } catch {
                syncError = "友達への共有を待っています。通信が戻ると再試行します。"
                return
            }
        }
    }

    /// 起動時に呼ぶ。初回はゲストアカウントを作り、端末内のレビューを友達に共有する。
    func start(sharing reviews: [LocalReview]) async {
        guard backend != nil else { return }
        do {
            _ = try await accessToken()
            await refresh()
            if libraryStore != nil { await flushReviews() }
            else { for review in reviews { try await upload(review) } }
            await refresh()
        } catch {
            status = .failed(connectionMessage(for: error))
        }
    }

    func refresh() async {
        guard backend != nil, !suspendsReviewSync else { return }
        let generation = identityGeneration
        refreshSequence += 1
        let sequence = refreshSequence
        do {
            async let me: Profile = call("/me")
            async let friends: [Friend] = paged("/friends")
            async let requests: [Request] = paged("/requests")
            async let reviews: [RemoteReview] = paged("/friend-reviews")
            let values = try await (me, friends, requests, reviews)
            guard generation == identityGeneration, sequence == refreshSequence, !suspendsReviewSync else { return }
            (self.me, self.friends, self.requests, self.friendReviews) = values
            status = .ready
            await rememberLocalEnvironment()
            await flushReviews()
        } catch {
            guard generation == identityGeneration, sequence == refreshSequence, !suspendsReviewSync else { return }
            status = .failed(connectionMessage(for: error))
        }
    }

    /// 相手のIDで申請する。見つからない・申請できないときは理由を返す。
    func sendRequest(handle raw: String) async -> String? {
        let handle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "@", with: "")
        guard (3...40).contains(handle.count), handle.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }) else {
            return "IDは英小文字・数字の3文字以上で入力してください。"
        }
        if handle == me?.handle { return "自分のIDです。友達のIDを入力してください。" }
        do {
            let found: [Profile] = try await call("/profiles", query: [URLQueryItem(name: "handle", value: handle)])
            guard let target = found.first else { return "そのIDの人が見つかりませんでした。" }
            let _: [String: String] = try await call("/requests", method: "POST", json: ["target_id": target.id])
            await refresh()
            return nil
        } catch CloudflareBackend.BackendError.http(409) {
            return "申請できませんでした。すでに友達か、相手から申請が届いていないか確認してください。"
        } catch {
            return "申請を送れませんでした。もう一度お試しください。"
        }
    }

    func respond(to request: Request, accept: Bool) async {
        await perform("/requests/\(request.id)", method: "PATCH", json: ["accept": accept])
    }

    func cancel(_ request: Request) async {
        await perform("/requests/\(request.id)", method: "DELETE")
    }

    func setFavorite(_ friend: Friend, _ isFavorite: Bool) async {
        await perform("/friends/\(friend.id)/favorite", method: isFavorite ? "PUT" : "DELETE")
    }

    func remove(_ friend: Friend) async {
        await perform("/friends/\(friend.id)", method: "DELETE")
    }

    func rename(_ displayName: String) async -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let me, (1...40).contains(name.count) else { actionError = "表示名は1〜40文字で入力してください。"; return false }
        do {
            let _: [String: Bool] = try await call("/me", method: "PATCH", json: ["display_name": name, "handle": me.handle])
            await refresh()
            return true
        } catch { actionError = "名前を変更できませんでした。もう一度お試しください。"; return false }
    }

    /// 評価・ひとこと・おすすめ料理だけを共有する。写真と来店日は端末内に残す。
    func upload(_ review: LocalReview) async throws {
        guard backend != nil else { return }
        let restaurantID = try await restaurantID(for: review.restaurant)
        let _: [String: String] = try await call("/reviews", method: "PUT", json: [
            "restaurant_id": restaurantID, "rating": review.rating, "comment": review.comment,
            "dish": review.dish, "want_again": review.wantAgain
        ])
    }

    func removeReview(for restaurant: SavedRestaurant) async throws {
        guard backend != nil else { return }
        let restaurantID = try await restaurantID(for: restaurant)
        struct Mine: Decodable { let id: String; let restaurantId: String }
        let mine: [Mine] = try await paged("/me/reviews")
        for review in mine where review.restaurantId == restaurantID {
            let _: [String: Bool] = try await call("/reviews/\(review.id)", method: "DELETE")
        }
    }

    private func restaurantID(for restaurant: SavedRestaurant) async throws -> String {
        struct Created: Decodable { let id: String }
        var body: [String: Any] = [
            "external_key": restaurant.id, "name": String(restaurant.name.prefix(200)),
            "latitude": restaurant.latitude, "longitude": restaurant.longitude,
            "address": String(restaurant.address.prefix(500))
        ]
        if let placeID = restaurant.googlePlaceID { body["google_place_id"] = placeID }
        if let category = restaurant.category { body["category"] = String(category.prefix(100)) }
        let created: Created = try await call("/restaurants", method: "POST", json: body)
        return created.id
    }

    private func perform(_ path: String, method: String, json: [String: Any]? = nil) async {
        do {
            let _: [String: Bool] = try await call(path, method: method, json: json)
        } catch {
            actionError = "変更できませんでした。もう一度お試しください。"
            return
        }
        await refresh()
    }

    private func accessToken() async throws -> String {
        guard !needsLocalReset else { throw CloudflareBackend.BackendError.invalidSession }
        if let token { return token }
        if let task = tokenTask { return try await task.value }
        if let saved = credentials.load() { token = saved; return saved }
        return try await createGuestToken()
    }

    private func createGuestToken() async throws -> String {
        guard !needsLocalReset, let backend else { throw CloudflareBackend.BackendError.invalidSession }
        if let task = tokenTask { return try await task.value }
        let task = Task { @MainActor in
            let guest = try await backend.signInAsGuest(displayName: environmentStore.string(forKey: "profile.name") ?? "ゲスト")
            guard credentials.save(guest.accessToken) else {
                try? await backend.signOut(accessToken: guest.accessToken)
                throw CocoaError(.fileWriteNoPermission)
            }
            return guest.accessToken
        }
        tokenTask = task
        defer { tokenTask = nil }
        let value = try await task.value
        token = value
        return value
    }

    /// A deployed account is never replaced on a 401. Development DB resets must be proven first.
    func call<T: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [],
                            json: [String: Any]? = nil) async throws -> T {
        guard let backend else { throw CloudflareBackend.BackendError.invalidSession }
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        let credential = try await accessToken()
        do {
            return try await backend.request(path, method: method, query: query, accessToken: credential, body: body)
        } catch CloudflareBackend.BackendError.http(401) {
            let replacement = try await recoverLocalGuest(rejected: credential)
            return try await backend.request(path, method: method, query: query, accessToken: replacement, body: body)
        }
    }

    private var environmentKey: String { "backend.instance." + (backend?.configuration.url.absoluteString ?? "") }

    private func recoverLocalGuest(rejected: String) async throws -> String {
        guard !needsLocalReset, let backend, backend.configuration.isDevelopmentHost else { throw CloudflareBackend.BackendError.http(401) }
        if let task = localRecoveryTask { return try await task.value }
        if let token, token != rejected { return token }
        let task = Task { @MainActor in
            let state: LocalEnvironment = try await backend.request("/auth/local-state")
            let previous = environmentStore.string(forKey: environmentKey)
            guard state.isEmpty || (previous != nil && previous != state.instanceId) else {
                throw CloudflareBackend.BackendError.http(401)
            }
            try libraryStore?.enqueueAllForSharing()
            let replacement = try await createGuestToken()
            environmentStore.set(state.instanceId, forKey: environmentKey)
            recordedLocalEnvironment = true
            me = nil; friends = []; requests = []; friendReviews = []
            return replacement
        }
        localRecoveryTask = task
        defer { localRecoveryTask = nil }
        return try await task.value
    }

    private func rememberLocalEnvironment() async {
        guard !recordedLocalEnvironment, let backend, backend.configuration.isDevelopmentHost else { return }
        if let state: LocalEnvironment = try? await backend.request("/auth/local-state") {
            environmentStore.set(state.instanceId, forKey: environmentKey)
            recordedLocalEnvironment = true
        }
    }

    private func connectionMessage(for error: Error) -> String {
        if case CloudflareBackend.BackendError.http(401) = error {
            return "認証情報を確認できませんでした。設定の引き継ぎコードで復旧してください。端末内の記録は保持しています。"
        }
        return "サーバーに接続できませんでした。通信状況を確認して再読み込みしてください。"
    }

    var connectionLabel: String {
        switch status {
        case .unavailable: return "この端末のプロフィール"
        case .connecting: return "接続を確認しています"
        case .ready: return "接続済み"
        case .failed: return "サーバーに接続できませんでした"
        }
    }

    func paged<T: Decodable>(_ path: String) async throws -> [T] {
        var results: [T] = []
        while true {
            let page: [T] = try await call(path, query: [URLQueryItem(name: "limit", value: "1000"),
                                                       URLQueryItem(name: "offset", value: String(results.count))])
            results += page
            if page.count < 1000 { return results }
        }
    }

    func transferData(_ path: String, method: String = "GET", data: Data? = nil) async throws -> Data {
        guard let backend else { throw CloudflareBackend.BackendError.invalidSession }
        let credential = try await accessToken()
        do { return try await backend.data(path, method: method, accessToken: credential, body: data, contentType: "image/jpeg") }
        catch CloudflareBackend.BackendError.http(401) {
            return try await backend.data(path, method: method, accessToken: try await recoverLocalGuest(rejected: credential), body: data, contentType: "image/jpeg")
        }
    }

    func updateProfile(name: String, bio: String, symbol: String) async throws {
        guard let me else { throw CloudflareBackend.BackendError.invalidSession }
        let _: [String: Bool] = try await call("/me", method: "PATCH", json: ["display_name": name, "handle": me.handle,
                                                                                 "bio": bio, "avatar_symbol": symbol])
        await refresh()
    }

    func loadSettings() async {
        do {
            async let prefs: Preferences = call("/preferences")
            async let blocks: [BlockedProfile] = paged("/blocks")
            (preferences, blockedProfiles) = try await (prefs, blocks)
        } catch { actionError = "設定を読み込めませんでした。もう一度お試しください。" }
    }

    func updatePreferences(allowSearch: Bool, includeInAverage: Bool) async throws {
        let _: [String: Bool] = try await call("/preferences", method: "PUT", json: ["allow_id_search": allowSearch,
                       "show_visit_date": false, "include_in_friend_avg": includeInAverage])
        await loadSettings()
    }

    func block(_ id: String) async {
        await perform("/blocks/\(id)", method: "PUT")
        await loadSettings()
    }

    func unblock(_ id: String) async {
        await perform("/blocks/\(id)", method: "DELETE")
        await loadSettings()
    }

    func makeRecoveryKey() async throws -> String {
        struct Key: Decodable { let recoveryKey: String }
        let result: Key = try await call("/me/recovery-key", method: "POST", json: [:])
        return result.recoveryKey
    }

    func recover(using key: String) async throws {
        guard let backend else { throw CloudflareBackend.BackendError.invalidSession }
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.count == 64, clean.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw CloudflareBackend.BackendError.invalidSession }
        // Await initial account creation before replacing its credential.
        if let task = tokenTask { _ = try await task.value }
        let session: CloudflareBackend.GuestSession = try await backend.request("/auth/recover", method: "POST",
                                         body: JSONEncoder().encode(["recovery_key":clean]))
        guard credentials.save(session.accessToken) else { throw CocoaError(.fileWriteNoPermission) }
        identityGeneration += 1
        token = session.accessToken
        me = nil; friends = []; requests = []; friendReviews = []
        // The caller restores the remote library before allowing any local uploads.
    }

    func restoreCredential(_ value: String?) throws {
        if let value {
            guard credentials.save(value) else { throw CocoaError(.fileWriteNoPermission) }
        } else { credentials.delete() }
        identityGeneration += 1
        token = value
    }

    func deleteAccount() async throws {
        let _: [String: Bool] = try await call("/me", method: "DELETE")
        needsLocalReset = true
        UserDefaults.standard.set(true, forKey: "account.needsLocalReset")
        identityGeneration += 1
        credentials.delete(); token = nil; me = nil; friends = []; requests = []; friendReviews = []
        preferences = nil; blockedProfiles = []; status = .unavailable
    }

    func finishLocalReset() {
        for key in ["profile.name", "profile.bio", "profile.symbol", "account.needsLocalReset"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        needsLocalReset = false
        suspendsReviewSync = false
    }

    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? .distantPast
    }
}
