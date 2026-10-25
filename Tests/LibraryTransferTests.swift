import MapKit
import XCTest
@testable import meshinowa

@MainActor
final class LibraryTransferTests: XCTestCase {
    nonisolated private static func requestBody(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    func testBackupAndRestorePreservePrivateFieldsAndDoNotDeleteAnotherAccountsReviews() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); BackendURLProtocol.handler = nil }
        let saved = SavedRestaurantStore(fileURL: directory.appendingPathComponent("saved.json"))
        let reviews = LocalReviewStore(fileURL: directory.appendingPathComponent("reviews.json"))
        let shop = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 139)))
        shop.name = "架空のバックアップ食堂"
        shop.googleDetails = GoogleRestaurantDetails(placeID: "backup-place")
        XCTAssertTrue(saved.setLiked(shop, isLiked: true))
        try reviews.save(item: shop, rating: 4.5, comment: "記録", dish: "カレー", wantAgain: true, visitedOn: Date(timeIntervalSince1970: 100))
        let credentials = MemoryGuestCredentials()
        XCTAssertTrue(credentials.save(String(repeating: "a", count: 64)))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendURLProtocol.self]
        let backend = CloudflareBackend(configuration: BackendConfiguration(url: URL(string: "https://api.example.test")!), session: URLSession(configuration: config))
        let friends = FriendStore(backend: backend, credentials: credentials)
        let transfer = LibraryTransfer()
        transfer.connect(saved: saved, reviews: reviews, friends: friends)
        var snapshot: Any = NSNull()
        var version = 0
        BackendURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/library":
                if request.httpMethod == "PUT" {
                    let body = try JSONSerialization.jsonObject(with: try Self.requestBody(request)) as! [String: Any]
                    snapshot = body["snapshot"]!
                    version += 1
                    return (200, try JSONSerialization.data(withJSONObject: ["version":version]))
                }
                return (200, try JSONSerialization.data(withJSONObject: ["version":version, "snapshot":snapshot]))
            case "/v1/auth/recover":
                return (200, Data("{\"access_token\":\"\(String(repeating: "b", count: 64))\",\"expires_at\":1,\"user_id\":\"00000000-0000-0000-0000-000000000002\"}".utf8))
            default: return (503, Data("{}".utf8))
            }
        }
        await transfer.backup()
        XCTAssertEqual(version, 1)
        XCTAssertTrue(transfer.message?.contains("バックアップしました") == true)
        let other = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 36, longitude: 140)))
        other.name = "別アカウントだけの店"
        try reviews.save(item: other, rating: 5, comment: "このアカウントだけ")
        await transfer.restore(recoveryKey: String(repeating: "c", count: 64))
        XCTAssertEqual(reviews.reviews.count, 1)
        XCTAssertEqual(reviews.reviews.first?.dish, "カレー")
        XCTAssertEqual(reviews.reviews.first?.visitedOn, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(saved.restaurants.first?.googlePlaceID, "backup-place")
        XCTAssertTrue(reviews.pending.allSatisfy { $0.review != nil })
        XCTAssertEqual(credentials.load(), String(repeating: "b", count: 64))
    }

    func testRecoveryWithoutBackupRestoresOriginalCredentialAndLocalData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); BackendURLProtocol.handler = nil }
        let saved = SavedRestaurantStore(fileURL: directory.appendingPathComponent("saved.json"))
        let reviews = LocalReviewStore(fileURL: directory.appendingPathComponent("reviews.json"))
        let credentials = MemoryGuestCredentials()
        let original = String(repeating: "a", count: 64)
        XCTAssertTrue(credentials.save(original))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendURLProtocol.self]
        let backend = CloudflareBackend(configuration: BackendConfiguration(url: URL(string: "https://api.example.test")!), session: URLSession(configuration: config))
        let friends = FriendStore(backend: backend, credentials: credentials)
        let transfer = LibraryTransfer()
        transfer.connect(saved: saved, reviews: reviews, friends: friends)
        BackendURLProtocol.handler = { request in
            if request.url?.path == "/v1/auth/recover" {
                return (200, Data("{\"access_token\":\"\(String(repeating: "b", count: 64))\",\"expires_at\":1,\"user_id\":\"00000000-0000-0000-0000-000000000002\"}".utf8))
            }
            return (200, Data("{\"version\":0,\"snapshot\":null}".utf8))
        }
        await transfer.restore(recoveryKey: String(repeating: "c", count: 64))
        XCTAssertEqual(credentials.load(), original)
        XCTAssertFalse(friends.suspendsReviewSync)
        XCTAssertTrue(transfer.message?.contains("バックアップがまだありません") == true)
    }
}
