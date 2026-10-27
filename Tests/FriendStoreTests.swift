import MapKit
import XCTest
@testable import meshinowa

@MainActor
final class FriendStoreTests: XCTestCase {
    private let credentials = MemoryGuestCredentials()
    private let token = String(repeating: "c", count: 64)
    private let testEnvironmentName = "jp.meshinowa.friend-tests." + UUID().uuidString
    private lazy var testEnvironment = UserDefaults(suiteName: testEnvironmentName)!

    override func tearDown() {
        credentials.delete()
        testEnvironment.removePersistentDomain(forName: testEnvironmentName)
        BackendURLProtocol.handler = nil
        super.tearDown()
    }

    private func store(url: String = "https://api.example.test", environmentStore: UserDefaults? = nil,
                       now: @escaping () -> Date = Date.init) -> FriendStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendURLProtocol.self]
        let backend = CloudflareBackend(configuration: BackendConfiguration(url: URL(string: url)!),
                                        session: URLSession(configuration: config))
        return FriendStore(backend: backend, credentials: credentials, environmentStore: environmentStore ?? testEnvironment, now: now)
    }

    func testProfileLookupNormalizesIDAndDoesNotSendRequest() async throws {
        XCTAssertTrue(credentials.save(token))
        var calls = 0
        BackendURLProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/profiles")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "handle" })?.value, "sakura_tabe")
            return (200, Data(#"[{"id":"f1","display_name":"さくら","handle":"sakura_tabe"}]"#.utf8))
        }
        let profile = try await store().findProfile(handle: "  @Sakura_Tabe\n")
        XCTAssertEqual(profile?.displayName, "さくら")
        XCTAssertEqual(calls, 1)
    }

    func testProfileLookupRejectsInvalidIDWithoutNetworkAndAllowsNoMatch() async throws {
        XCTAssertTrue(credentials.save(token))
        var calls = 0
        BackendURLProtocol.handler = { _ in
            calls += 1
            return (200, Data("[]".utf8))
        }
        let store = store()
        do {
            _ = try await store.findProfile(handle: "さくら")
            XCTFail("不正なIDでは通信しない")
        } catch is FriendStore.ProfileSearchError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(calls, 0)
        let profile = try await store.findProfile(handle: "unknown")
        XCTAssertNil(profile)
        XCTAssertEqual(calls, 1)
    }

    func testRequestUsesConfirmedProfileIDWithoutSecondLookup() async throws {
        XCTAssertTrue(credentials.save(token))
        var posts = 0
        BackendURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/requests" where request.httpMethod == "POST":
                posts += 1
                return (201, Data(#"{"id":"r1"}"#.utf8))
            case "/v1/me":
                return (200, Data(#"{"id":"me","display_name":"自分","handle":"my_id"}"#.utf8))
            case "/v1/requests":
                return (200, Data(#"[{"id":"r1","from_id":"me","to_id":"f1","status":"pending","from_name":"自分","from_handle":"my_id","to_name":"さくら","to_handle":"new_handle"}]"#.utf8))
            case "/v1/friends", "/v1/friend-reviews":
                return (200, Data("[]".utf8))
            default:
                XCTFail("確認済みなら再検索しない: \(request.url?.path ?? "")")
                return (404, Data("{}".utf8))
            }
        }
        let store = store()
        let selected = FriendStore.Profile(id: "f1", displayName: "さくら", handle: "old_handle")
        let error = await store.sendRequest(to: selected)
        XCTAssertNil(error)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(store.outgoingRequests.first?.toId, selected.id)
    }

    func testReviewDateAcceptsTimestampsWithAndWithoutFractionalSeconds() {
        let expected = Date(timeIntervalSince1970: 1_761_408_000)
        let whole = FriendStore.date("2025-10-25T16:00:00Z")
        XCTAssertEqual(whole, expected)
        let fractional = FriendStore.date("2025-10-25T16:00:00.456Z")
        XCTAssertEqual(fractional.timeIntervalSince(whole), 0.456, accuracy: 0.001)
        XCTAssertEqual(FriendStore.date("invalid"), .distantPast)
    }

    func testNewConnectionAnnouncementStartsAfterInitialLoadAndDoesNotRepeat() async {
        XCTAssertTrue(credentials.save(token))
        var includesNewFriend = false
        BackendURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/me":
                return (200, Data(#"{"id":"me","display_name":"自分","handle":"my_id"}"#.utf8))
            case "/v1/friends":
                let existing = #"{"id":"f1","display_name":"既存の友達","handle":"friend1","is_favorite":0}"#
                let added = #"{"id":"f2","display_name":"新しい友達","handle":"friend2","is_favorite":0}"#
                return (200, Data((includesNewFriend ? "[\(existing),\(added)]" : "[\(existing)]").utf8))
            case "/v1/requests", "/v1/friend-reviews": return (200, Data("[]".utf8))
            default: return (404, Data("{}".utf8))
            }
        }
        let store = store()
        await store.refresh()
        XCTAssertTrue(store.newConnections.isEmpty)
        includesNewFriend = true
        await store.refresh()
        XCTAssertEqual(store.newConnections.map(\.id), ["f2"])
        await store.refresh()
        XCTAssertEqual(store.newConnections.count, 1)
        store.dismissNewConnection("f2")
        await store.refresh()
        XCTAssertTrue(store.newConnections.isEmpty)
        includesNewFriend = false
        await store.refresh()
        includesNewFriend = true
        await store.refresh()
        XCTAssertEqual(store.newConnections.map(\.id), ["f2"])
        includesNewFriend = false
        await store.refresh()
        XCTAssertTrue(store.newConnections.isEmpty)
    }

    func testApprovalAnnouncementOnlyAppearsAfterSuccessfulAcceptance() async throws {
        XCTAssertTrue(credentials.save(token))
        var accepted = false
        var fails = true
        BackendURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/requests/r1":
                if fails { return (503, Data("{}".utf8)) }
                accepted = true
                return (200, Data(#"{"ok":true}"#.utf8))
            case "/v1/me":
                return (200, Data(#"{"id":"me","display_name":"自分","handle":"my_id"}"#.utf8))
            case "/v1/friends":
                return (200, Data((accepted ? #"[{"id":"f1","display_name":"さくら","handle":"sakura","is_favorite":0}]"# : "[]").utf8))
            case "/v1/requests":
                return (200, Data((accepted ? "[]" : #"[{"id":"r1","from_id":"f1","to_id":"me","status":"pending","from_name":"さくら","from_handle":"sakura","to_name":"自分","to_handle":"my_id"}]"#).utf8))
            case "/v1/friend-reviews": return (200, Data("[]".utf8))
            default: return (404, Data("{}".utf8))
            }
        }
        let store = store()
        await store.refresh()
        let request = try XCTUnwrap(store.incomingRequests.first)
        await store.respond(to: request, accept: true)
        XCTAssertTrue(store.newConnections.isEmpty)
        XCTAssertEqual(store.incomingRequests.count, 1)
        XCTAssertNotNil(store.actionError)
        fails = false
        await store.respond(to: request, accept: true)
        XCTAssertEqual(store.newConnections.map(\.id), ["f1"])
        XCTAssertTrue(store.incomingRequests.isEmpty)
    }

    func testConnectionAnnouncementsSurviveRelaunchAndRememberDismissal() async {
        XCTAssertTrue(credentials.save(token))
        var connected = false
        var profileID = "me"
        BackendURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/me":
                return (200, Data(#"{"id":"\#(profileID)","display_name":"自分","handle":"my_id"}"#.utf8))
            case "/v1/friends":
                return (200, Data((connected ? #"[{"id":"f1","display_name":"さくら","handle":"sakura","is_favorite":0}]"# : "[]").utf8))
            case "/v1/requests", "/v1/friend-reviews": return (200, Data("[]".utf8))
            default: return (404, Data("{}".utf8))
            }
        }
        let beforeApproval = store()
        await beforeApproval.refresh()
        XCTAssertTrue(beforeApproval.newConnections.isEmpty)
        connected = true
        let afterRelaunch = store()
        await afterRelaunch.refresh()
        XCTAssertEqual(afterRelaunch.newConnections.map(\.id), ["f1"])
        profileID = "other-account"
        let otherAccount = store()
        await otherAccount.refresh()
        XCTAssertTrue(otherAccount.newConnections.isEmpty)
        profileID = "me"
        let stillPending = store()
        await stillPending.refresh()
        XCTAssertEqual(stillPending.newConnections.map(\.id), ["f1"])
        stillPending.dismissNewConnection("f1")
        let dismissed = store()
        await dismissed.refresh()
        XCTAssertTrue(dismissed.newConnections.isEmpty)
    }

    func testWithoutBackendStaysUnavailable() async {
        let store = FriendStore(backend: nil, credentials: credentials)
        await store.start(sharing: [])
        XCTAssertEqual(store.status, .unavailable)
        XCTAssertNil(credentials.load())
        XCTAssertTrue(store.dataset.friends.isEmpty)
        XCTAssertTrue(store.dataset.restaurants.isEmpty)
        XCTAssertTrue(store.dataset.reviews.isEmpty)
        XCTAssertTrue(store.dataset.ratedRestaurants.isEmpty)
    }

    func testStartCreatesGuestOnceAndBuildsFriendDataset() async throws {
        var guestCalls = 0
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)))
        item.name = "架空の食堂"
        let key = SavedRestaurant.identifier(for: item)
        BackendURLProtocol.handler = { [token] request in
            let path = request.url?.path ?? ""
            if path == "/v1/auth/guest" {
                guestCalls += 1
                return (201, Data("{\"access_token\":\"\(token)\",\"expires_at\":1,\"user_id\":\"00000000-0000-0000-0000-000000000001\"}".utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            switch path {
            case "/v1/me":
                return (200, Data("{\"id\":\"me\",\"display_name\":\"ゲスト\",\"handle\":\"abc2345\"}".utf8))
            case "/v1/friends":
                return (200, Data("[{\"id\":\"f1\",\"display_name\":\"はなこ\",\"handle\":\"hanako1\",\"is_favorite\":1}]".utf8))
            case "/v1/requests":
                return (200, Data("[{\"id\":\"r1\",\"from_id\":\"f2\",\"to_id\":\"me\",\"status\":\"pending\",\"from_name\":\"たろう\",\"from_handle\":\"taro123\",\"to_name\":\"ゲスト\",\"to_handle\":\"abc2345\"}]".utf8))
            case "/v1/friend-reviews":
                let review = "{\"id\":\"v1\",\"user_id\":\"f1\",\"display_name\":\"はなこ\",\"rating\":4.5,\"comment\":\"架空のひとこと\",\"dish\":\"\",\"updated_at\":\"2026-10-25T01:02:03.456Z\",\"restaurant_id\":\"s1\",\"external_key\":\"\(key)\",\"name\":\"架空の食堂\",\"category\":\"MKPOICategoryCafe\",\"address\":\"東京都\",\"latitude\":35.68,\"longitude\":139.76}"
                return (200, Data("[\(review)]".utf8))
            default:
                XCTFail("Unexpected path \(path)")
                return (404, Data("{}".utf8))
            }
        }
        let store = store()
        await store.start(sharing: [])
        await store.refresh()

        XCTAssertEqual(guestCalls, 1)
        XCTAssertEqual(credentials.load(), token)
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.me?.handle, "abc2345")
        XCTAssertEqual(store.incomingRequests.map(\.fromName), ["たろう"])
        XCTAssertTrue(store.outgoingRequests.isEmpty)

        let dataset = store.dataset
        XCTAssertEqual(dataset.favoriteFriendIDs, ["f1"])
        XCTAssertEqual(dataset.restaurants.map(\.genre), ["カフェ"])
        XCTAssertEqual(dataset.friendName("f1"), "はなこ")
        let summary = store.summary(for: item)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.average, 4.5)
        XCTAssertNil(store.summary(for: item, friendIDs: []).average)
        XCTAssertEqual(store.summary(for: item, friendIDs: ["f1"]).count, 1)
        XCTAssertEqual(store.ratingText(for: item), "友達1人の評価 4.5")
    }
    func testFailedSharingRemainsQueuedAndRetriesAfterRelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("reviews.json")
        let local = LocalReviewStore(fileURL: file)
        let shop = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 139)))
        shop.name = "架空の同期食堂"
        try local.save(item: shop, rating: 4.5, comment: "queued")
        XCTAssertTrue(credentials.save(token))
        var failUpload = true
        BackendURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/restaurants": return (201, Data("{\"id\":\"shop\"}".utf8))
            case "/v1/reviews": return failUpload ? (503, Data("{}".utf8)) : (200, Data("{\"id\":\"review\"}".utf8))
            default: return (404, Data("{}".utf8))
            }
        }
        let first = store()
        first.connect(to: local)
        await first.flushReviews()
        XCTAssertNotNil(first.syncError)
        XCTAssertEqual(local.pending.count, 1)
        let reloaded = LocalReviewStore(fileURL: file)
        let second = store()
        second.connect(to: reloaded)
        failUpload = false
        await second.flushReviews()
        XCTAssertTrue(reloaded.pending.isEmpty)
        XCTAssertNil(second.syncError)
    }

    func testExpiredSessionNeverSilentlyCreatesNewIdentity() async throws {
        XCTAssertTrue(credentials.save(token))
        var guestCalls = 0
        BackendURLProtocol.handler = { request in
            if request.url?.path == "/v1/auth/guest" { guestCalls += 1 }
            return (401, Data("{}".utf8))
        }
        let store = store()
        await store.refresh()
        XCTAssertEqual(guestCalls, 0)
        XCTAssertEqual(credentials.load(), token)
        guard case .failed = store.status else { return XCTFail("Expected explicit failure") }
    }

    func testConcurrentCallsShareGuestCreation() async throws {
        var guestCalls = 0
        BackendURLProtocol.handler = { [token] request in
            if request.url?.path == "/v1/auth/guest" {
                guestCalls += 1
                return (201, Data("{\"access_token\":\"\(token)\",\"expires_at\":1,\"user_id\":\"00000000-0000-0000-0000-000000000001\"}".utf8))
            }
            return (200, Data("{\"id\":\"me\",\"display_name\":\"ゲスト\",\"handle\":\"abc2345\"}".utf8))
        }
        let store = store()
        async let a: FriendStore.Profile = store.call("/me")
        async let b: FriendStore.Profile = store.call("/me")
        async let c: FriendStore.Profile = store.call("/me")
        _ = try await (a,b,c)
        XCTAssertEqual(guestCalls, 1)
    }

    func testCredentialWriteFailureDoesNotExposeAnUnpersistedAccount() async throws {
        credentials.rejectsWrites = true
        var deleteCalls = 0
        BackendURLProtocol.handler = { [token] request in
            if request.url?.path == "/v1/auth/guest" {
                return (201, Data("{\"access_token\":\"\(token)\",\"expires_at\":1,\"user_id\":\"00000000-0000-0000-0000-000000000001\"}".utf8))
            }
            if request.url?.path == "/v1/me", request.httpMethod == "DELETE" { deleteCalls += 1; return (200, Data("{\"ok\":true}".utf8)) }
            XCTFail("Must not use the unpersisted session")
            return (500, Data("{}".utf8))
        }
        let store = store()
        await store.start(sharing: [])
        XCTAssertNil(store.me)
        XCTAssertNil(credentials.load())
        XCTAssertEqual(deleteCalls, 1)
    }

    func testCredentialWriteFailureStopsAutomaticGuestCreationUntilUserRetries() async throws {
        credentials.rejectsWrites = true
        var guestCalls = 0
        var revokeCalls = 0
        var sessionSaved = false
        BackendURLProtocol.handler = { [token] request in
            switch request.url?.path ?? "" {
            case "/v1/auth/guest":
                guestCalls += 1
                return (201, Data("{\"access_token\":\"\(token)\",\"expires_at\":1,\"user_id\":\"00000000-0000-0000-0000-000000000001\"}".utf8))
            case "/v1/me" where request.httpMethod == "DELETE":
                return (500, Data("{}".utf8))  // 削除できなくても、少なくともセッションは失効させる
            case "/v1/auth/session":
                revokeCalls += 1
                return (200, Data("{}".utf8))
            default:
                if !sessionSaved { XCTFail("Must not use the unpersisted session") }
                return (500, Data("{}".utf8))
            }
        }
        let store = store()
        await store.start(sharing: [])
        for _ in 0..<3 { await store.refresh() }  // 10秒ごとの定期更新に相当
        XCTAssertEqual(guestCalls, 1)
        XCTAssertEqual(revokeCalls, 1)
        guard case .failed(let message) = store.status else { return XCTFail("Expected explicit failure") }
        XCTAssertTrue(message.contains("保存できなかった"))

        await store.retryConnection()
        XCTAssertEqual(guestCalls, 2)
        XCTAssertNil(credentials.load())

        credentials.rejectsWrites = false
        sessionSaved = true
        await store.retryConnection()
        XCTAssertEqual(guestCalls, 3)
        XCTAssertEqual(credentials.load(), token)
    }

    func testDeletedAccountCannotUploadOldDataBeforeLocalResetCompletes() async throws {
        let oldFlag = UserDefaults.standard.object(forKey: "account.needsLocalReset")
        defer {
            if let oldFlag { UserDefaults.standard.set(oldFlag, forKey: "account.needsLocalReset") }
            else { UserDefaults.standard.removeObject(forKey: "account.needsLocalReset") }
        }
        UserDefaults.standard.removeObject(forKey: "account.needsLocalReset")
        XCTAssertTrue(credentials.save(token))
        var guestCalls = 0
        BackendURLProtocol.handler = { request in
            if request.url?.path == "/v1/auth/guest" { guestCalls += 1 }
            return (200, Data("{\"ok\":true}".utf8))
        }
        let store = store()
        try await store.deleteAccount()
        XCTAssertTrue(store.needsLocalReset)
        await store.start(sharing: [])
        XCTAssertEqual(guestCalls, 0)
        XCTAssertNil(credentials.load())
    }

    func testLocalDatabaseRecoveryRequiresEmptyDatabaseOrChangedInstance() async throws {
        let origin = "http://localhost:8787"
        let cases: [(Bool,String?,Int)] = [(true,nil,1),(false,"old-instance",1),(false,"current-instance",0),(false,nil,0)]
        for (empty,previous,expectedCreations) in cases {
            let domain = "meshinowa-tests-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer { defaults.removePersistentDomain(forName: domain) }
            if let previous { defaults.set(previous,forKey: "backend.instance." + origin) }
            XCTAssertTrue(credentials.save(token))
            let replacement = String(repeating: "d", count: 64)
            var creations = 0
            BackendURLProtocol.handler = { [token] request in
                let path = request.url?.path
                if path == "/v1/auth/local-state" {
                    return (200, Data("{\"instance_id\":\"current-instance\",\"is_empty\":\(empty ? "true" : "false")}".utf8))
                }
                if path == "/v1/auth/guest" {
                    creations += 1
                    return (201, Data("{\"access_token\":\"\(replacement)\",\"expires_at\":1,\"user_id\":\"00000000-0000-0000-0000-000000000001\"}".utf8))
                }
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer " + token { return (401, Data("{}".utf8)) }
                if path == "/v1/me" { return (200, Data("{\"id\":\"me\",\"display_name\":\"ゲスト\",\"handle\":\"abc2345\"}".utf8)) }
                return (200, Data("[]".utf8))
            }
            let store = store(url: origin, environmentStore: defaults)
            await store.refresh()
            XCTAssertEqual(creations,expectedCreations)
            XCTAssertEqual(credentials.load(),expectedCreations == 1 ? replacement : token)
            if expectedCreations == 1 {
                XCTAssertEqual(store.status,.ready)
                XCTAssertEqual(store.me?.handle,"abc2345")
                XCTAssertEqual(defaults.string(forKey:"backend.instance." + origin),"current-instance")
            } else {
                guard case .failed = store.status else { return XCTFail("Expected explicit authentication failure") }
                XCTAssertNotEqual(store.connectionLabel,"接続を確認しています")
            }
        }
    }

    func testAutomaticRefreshIsSharedAndManualRefreshBypassesInterval() async throws {
        XCTAssertTrue(credentials.save(token))
        var clock = Date(timeIntervalSince1970: 1000)
        let subject = store(now: { clock })
        let lock = NSLock()
        var requests = 0
        BackendURLProtocol.handler = { request in
            lock.lock(); requests += 1; lock.unlock()
            if request.url?.path == "/v1/me" {
                return (200, Data("{\"id\":\"me\",\"display_name\":\"ゲスト\",\"handle\":\"test123\"}".utf8))
            }
            return (200, Data("[]".utf8))
        }
        async let first: Void = subject.refreshIfNeeded()
        async let second: Void = subject.refreshIfNeeded()
        _ = await (first, second)
        XCTAssertEqual(requests, 4)
        clock = clock.addingTimeInterval(59)
        await subject.refreshIfNeeded()
        XCTAssertEqual(requests, 4)
        clock = clock.addingTimeInterval(1)
        await subject.refreshIfNeeded()
        XCTAssertEqual(requests, 8)
        await subject.refresh()
        XCTAssertEqual(requests, 12)
    }

    func testPeriodicReviewRetryWaitsButImmediateSaveCanRetry() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let local = LocalReviewStore(fileURL: folder.appendingPathComponent("reviews.json"))
        XCTAssertTrue(credentials.save(token))
        var clock = Date(timeIntervalSince1970: 1000)
        let subject = store(now: { clock })
        subject.connect(to: local)
        var uploads = 0
        BackendURLProtocol.handler = { request in
            if request.url?.path == "/v1/restaurants" { return (200, Data("{\"id\":\"shop\"}".utf8)) }
            if request.url?.path == "/v1/reviews" { uploads += 1; return (503, Data("{}".utf8)) }
            XCTFail("不要な通信です")
            return (404, Data())
        }
        await subject.flushReviewsIfNeeded()
        XCTAssertEqual(uploads, 0)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 139)))
        item.name = "再試行のテスト店舗"
        try local.save(item: item, rating: 4, comment: "未送信")
        await subject.flushReviewsIfNeeded()
        await subject.flushReviewsIfNeeded()
        XCTAssertEqual(uploads, 1)
        XCTAssertEqual(local.pending.count, 1)
        clock = clock.addingTimeInterval(60)
        await subject.flushReviewsIfNeeded()
        XCTAssertEqual(uploads, 2)
        await subject.flushReviews()
        XCTAssertEqual(uploads, 3)
    }

}

final class MemoryGuestCredentials: GuestCredentials {
    var token: String?
    var rejectsWrites = false
    func load() -> String? { token }
    func save(_ value: String) -> Bool { guard !rejectsWrites else { return false }; token = value; return true }
    func delete() { token = nil }

}
