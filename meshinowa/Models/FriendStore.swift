import Combine
import Foundation
import MapKit

/// ゲストアカウントと友達のつながり・評価。Cloudflare未設定なら何も送らず、友達のデータは空になる。
@MainActor
final class FriendStore: ObservableObject {
    struct Profile: Decodable, Equatable {
        let id: String
        let displayName: String
        let handle: String
    }

    struct Friend: Decodable, Identifiable {
        let id: String
        let displayName: String
        let handle: String
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
        let externalKey: String
        let name: String
        let category: String?
        let address: String
        let latitude: Double
        let longitude: Double
    }

    enum Status: Equatable { case unavailable, connecting, ready, failed(String) }

    @Published private(set) var status: Status
    @Published private(set) var me: Profile?
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var requests: [Request] = []
    @Published private(set) var friendReviews: [RemoteReview] = []

    @Published private var presentationData: FriendDataset?
    private var initialPresentationData: FriendDataset?
    private var isResolvingPresentation = false
    private var didResolvePresentation = false
    private let presentationLoader: () async throws -> PresentationDemo.Resolution
    private let backend: CloudflareBackend?
    private let credentials: GuestCredentialStore
    private var token: String?

    init(backend: CloudflareBackend? = try? CloudflareBackend.makeClient(),
         credentials: GuestCredentialStore = GuestCredentialStore(), presentation: FriendDataset? = nil,
         presentationLoader: (() async throws -> PresentationDemo.Resolution)? = nil) {
        self.presentationData = presentation
        self.initialPresentationData = presentation
        self.didResolvePresentation = presentation?.restaurants.isEmpty == false
        self.presentationLoader = presentationLoader ?? { try await PresentationDemo.resolveStores() }
        self.backend = presentation == nil ? backend : nil
        self.credentials = credentials
        status = presentation != nil ? .ready : (backend == nil ? .unavailable : .connecting)
        if let presentation { loadPresentation(presentation) }
    }

    private func loadPresentation(_ data: FriendDataset) {
        presentationData = data
        me = Profile(id: "demo-me", displayName: "発表ユーザー", handle: "kit_demo")
        friends = data.friends.map {
            Friend(id: $0.id, displayName: $0.name, handle: $0.id.replacingOccurrences(of: "-", with: "_"),
                   isFavorite: data.favoriteFriendIDs.contains($0.id) ? 1 : 0)
        }
        status = data.restaurants.isEmpty ? .connecting : .ready
    }

    func resetPresentation() {
        guard isPresentation, let data = initialPresentationData else { return }
        loadPresentation(data)
    }

    var isAvailable: Bool { backend != nil || presentationData != nil }
    var isPresentation: Bool { presentationData != nil }
    var incomingRequests: [Request] { requests.filter { $0.status == "pending" && $0.toId == me?.id } }
    var outgoingRequests: [Request] { requests.filter { $0.status == "pending" && $0.fromId == me?.id } }

    var dataset: FriendDataset {
        if let presentationData { return presentationData }
        var restaurants: [String: FriendRestaurant] = [:]
        for review in friendReviews where restaurants[review.externalKey] == nil {
            let category = MKMapItem()
            category.pointOfInterestCategory = review.category.map(MKPointOfInterestCategory.init(rawValue:))
            restaurants[review.externalKey] = FriendRestaurant(
                id: review.externalKey, name: review.name, genre: category.restaurantCategory,
                coordinate: CLLocationCoordinate2D(latitude: review.latitude, longitude: review.longitude),
                address: review.address, category: review.category)
        }
        return FriendDataset(
            friends: friends.map { FriendProfile(id: $0.id, name: $0.displayName) },
            favoriteFriendIDs: Set(friends.filter { $0.isFavorite != 0 }.map(\.id)),
            restaurants: restaurants.values.sorted { $0.name < $1.name },
            reviews: friendReviews.map {
                FriendReview(id: $0.id, friendID: $0.userId, restaurantID: $0.externalKey, rating: $0.rating,
                             comment: $0.comment, updatedAt: Self.date($0.updatedAt), dish: $0.dish)
            })
    }

    /// 地図検索のお店に付いた友達の評価。照合キーは保存・レビューと同じ店名＋座標。
    func summary(for item: MKMapItem) -> FriendRatingSummary {
        FriendRatingSummary(restaurantID: SavedRestaurant.identifier(for: item), reviews: dataset.reviews)
    }

    /// 起動時に呼ぶ。初回はゲストアカウントを作り、端末内のレビューを友達に共有する。
    func start(sharing reviews: [LocalReview]) async {
        if isPresentation { await refresh(); return }
        guard backend != nil else { return }
        do {
            _ = try await accessToken()
            await refresh()
            for review in reviews { try? await upload(review) }
            await refresh()
        } catch {
            status = .failed("サーバーに接続できませんでした。通信状況を確認して、もう一度お試しください。")
        }
    }

    func refresh(force: Bool = false) async {
        if isPresentation {
            guard !isResolvingPresentation, force || !didResolvePresentation else { return }
            isResolvingPresentation = true
            status = .connecting
            defer { isResolvingPresentation = false }
            do {
                let result = try await presentationLoader()
                initialPresentationData = result.dataset
                loadPresentation(result.dataset)
                didResolvePresentation = true
                if !result.missingNames.isEmpty {
                    status = .failed("一部の店舗情報をGoogleから取得できませんでした。下に引いて再読み込みできます。")
                }
            } catch {
                status = .failed("店舗情報をGoogleから取得できませんでした。通信と設定を確認し、下に引いて再読み込みしてください。")
            }
            return
        }
        guard backend != nil else { return }
        do {
            async let me: Profile = call("/me")
            async let friends: [Friend] = call("/friends")
            async let requests: [Request] = call("/requests")
            async let reviews: [RemoteReview] = call("/friend-reviews")
            (self.me, self.friends, self.requests, self.friendReviews) = try await (me, friends, requests, reviews)
            status = .ready
        } catch {
            status = .failed("友達の情報を読み込めませんでした。下に引っ張って再読み込みしてください。")
        }
    }

    /// 相手のIDで申請する。見つからない・申請できないときは理由を返す。
    func sendRequest(handle raw: String) async -> String? {
        if isPresentation { return "発表デモでは、用意された6人の友達でお試しください。" }
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
        if var data = presentationData {
            if isFavorite { data.favoriteFriendIDs.insert(friend.id) }
            else { data.favoriteFriendIDs.remove(friend.id) }
            presentationData = data
            if let index = friends.firstIndex(where: { $0.id == friend.id }) {
                friends[index] = Friend(id: friend.id, displayName: friend.displayName, handle: friend.handle, isFavorite: isFavorite ? 1 : 0)
            }
            return
        }
        await perform("/friends/\(friend.id)/favorite", method: isFavorite ? "PUT" : "DELETE")
    }

    func remove(_ friend: Friend) async {
        if var data = presentationData {
            data.friends.removeAll { $0.id == friend.id }
            data.favoriteFriendIDs.remove(friend.id)
            data.reviews.removeAll { $0.friendID == friend.id }
            data.restaurants.removeAll { shop in !data.reviews.contains { $0.restaurantID == shop.id } }
            presentationData = data
            friends.removeAll { $0.id == friend.id }
            return
        }
        await perform("/friends/\(friend.id)", method: "DELETE")
    }

    func rename(_ displayName: String) async -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let me, (1...40).contains(name.count) else { return false }
        if isPresentation {
            self.me = Profile(id: me.id, displayName: name, handle: me.handle)
            return true
        }
        do {
            let _: [String: Bool] = try await call("/me", method: "PATCH", json: ["display_name": name, "handle": me.handle])
            await refresh()
            return true
        } catch { return false }
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
        let mine: [Mine] = try await call("/me/reviews")
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
        if let category = restaurant.category { body["category"] = String(category.prefix(100)) }
        let created: Created = try await call("/restaurants", method: "POST", json: body)
        return created.id
    }

    private func perform(_ path: String, method: String, json: [String: Any]? = nil) async {
        guard !isPresentation else { return }
        do {
            let _: [String: Bool] = try await call(path, method: method, json: json)
        } catch {
            status = .failed("変更できませんでした。もう一度お試しください。")
        }
        await refresh()
    }

    private func accessToken() async throws -> String {
        if let token { return token }
        if let saved = credentials.load() { token = saved; return saved }
        guard let backend else { throw CloudflareBackend.BackendError.invalidSession }
        let guest = try await backend.signInAsGuest(displayName: "ゲスト")
        _ = credentials.save(guest.accessToken)
        token = guest.accessToken
        return guest.accessToken
    }

    private func call<T: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [],
                                    json: [String: Any]? = nil) async throws -> T {
        guard let backend else { throw CloudflareBackend.BackendError.invalidSession }
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        do {
            return try await backend.request(path, method: method, query: query,
                                             accessToken: try await accessToken(), body: body)
        } catch CloudflareBackend.BackendError.http(401) {
            // セッションが無効になったゲストは作り直す。以前の友達とのつながりは引き継げない。
            credentials.delete()
            token = nil
            return try await backend.request(path, method: method, query: query,
                                             accessToken: try await accessToken(), body: body)
        }
    }

    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? .distantPast
    }
}
