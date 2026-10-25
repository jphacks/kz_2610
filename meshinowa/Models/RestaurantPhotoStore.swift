import Foundation
import ImageIO
import MapKit
import UIKit

struct RestaurantPhotoQuery: Encodable, Hashable {
    let name: String
    let latitude: Double
    let longitude: Double

    init(name: String, latitude: Double, longitude: Double) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latitude = (latitude * 100_000).rounded() / 100_000
        self.longitude = (longitude * 100_000).rounded() / 100_000
    }

    init(item: MKMapItem) {
        self.init(name: item.name ?? "", latitude: item.placemark.coordinate.latitude,
                  longitude: item.placemark.coordinate.longitude)
    }
}

struct HotPepperPhoto: Decodable {
    let shopId: String
    let name: String
    let imageUrl: URL
    let thumbnailUrl: URL
    let shopUrl: URL

    var hasSafeURLs: Bool {
        [imageUrl, thumbnailUrl].allSatisfy { Self.isProviderURL($0, hosts: ["imgfp.hotp.jp"]) }
            && Self.isProviderURL(shopUrl, hosts: ["www.hotpepper.jp", "hotpepper.jp"])
    }

    private static func isProviderURL(_ url: URL, hosts: [String]) -> Bool {
        url.scheme == "https" && hosts.contains(url.host ?? "") && url.user == nil
            && url.password == nil && url.port == nil
    }
}

struct RestaurantPhotoAsset {
    let photo: HotPepperPhoto
    let image: UIImage
}

/// 店名と店舗座標だけを送信する。保存・レビュー・ユーザーの現在地は送らない。
/// 画像はメモリ内だけに置き、画面を移動しても再利用する。最長1時間で更新。
@MainActor
final class RestaurantPhotoStore {
    static let shared = RestaurantPhotoStore()
    typealias Loader = (RestaurantPhotoQuery) async throws -> RestaurantPhotoAsset?

    private struct Entry {
        let asset: RestaurantPhotoAsset?
        let expiresAt: Date
    }
    private var cache: [RestaurantPhotoQuery: Entry] = [:]
    private var inFlight: [RestaurantPhotoQuery: Task<RestaurantPhotoAsset?, Never>] = [:]
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let loader: Loader
    private let clock: () -> Date

    init(loader: Loader? = nil, clock: @escaping () -> Date = Date.init) {
        self.loader = loader ?? Self.fetch
        self.clock = clock
    }

    func cached(for query: RestaurantPhotoQuery) -> RestaurantPhotoAsset? {
        guard let entry = cache[query], entry.expiresAt > clock() else { return nil }
        return entry.asset
    }

    func refreshInterval(for query: RestaurantPhotoQuery) -> TimeInterval {
        guard let entry = cache[query] else { return 30 }
        return max(1, min(300, entry.expiresAt.timeIntervalSince(clock())))
    }

    func asset(for query: RestaurantPhotoQuery) async -> RestaurantPhotoAsset? {
        guard !query.name.isEmpty, query.latitude.isFinite, query.longitude.isFinite,
              (-90...90).contains(query.latitude), (-180...180).contains(query.longitude) else { return nil }
        if let entry = cache[query], entry.expiresAt > clock() { return entry.asset }
        if let task = inFlight[query] { return await task.value }
        let task = Task<RestaurantPhotoAsset?, Never> {
            await acquire()
            defer { release() }
            let asset: RestaurantPhotoAsset?
            let ttl: TimeInterval
            do {
                asset = try await loader(query)
                ttl = asset == nil ? 300 : 3600
            } catch {
                asset = nil
                ttl = 30 // 通信失敗を永続的な「写真なし」として扱わない。
            }
            cache = cache.filter { $0.value.expiresAt > clock() }
            // A decoded image is bounded to 600px; retain at most 24 images (~35MB).
            if cache.count >= 24, let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                cache.removeValue(forKey: oldest)
            }
            cache[query] = Entry(asset: asset, expiresAt: clock().addingTimeInterval(ttl))
            return asset
        }
        inFlight[query] = task
        let result = await task.value
        inFlight[query] = nil
        return result
    }

    private func acquire() async {
        if active < 4 { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { active -= 1 } else { waiters.removeFirst().resume() }
    }

    private struct LookupResponse: Decodable { let photo: HotPepperPhoto? }
    private static func fetch(_ query: RestaurantPhotoQuery) async throws -> RestaurantPhotoAsset? {
        guard var backend = try CloudflareBackend.makeClient() else { return nil }
        backend.session = RestaurantPhotoDownloader.session
        let result: LookupResponse = try await backend.request("/restaurant-photo", method: "POST",
                                                              body: JSONEncoder().encode(query))
        guard let photo = result.photo, photo.hasSafeURLs else { return nil }
        guard let image = try await RestaurantPhotoDownloader.image(for: photo) else { return nil }
        return RestaurantPhotoAsset(photo: photo, image: image)
    }
}

private enum RestaurantPhotoDownloader {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    // Nonisolated async code keeps streaming and image decoding off the main actor.
    static func image(for photo: HotPepperPhoto) async throws -> UIImage? {
        // Download directly from the provider, never from an arbitrary URL or through R2.
        // No user session is sent to the image host; redirects are rejected.
        var request = URLRequest(url: photo.imageUrl)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: request, delegate: PhotoRedirectDelegate())
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true,
              response.expectedContentLength <= 5 * 1024 * 1024 else { return nil }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 5 * 1024 * 1024 { throw URLError(.dataLengthExceedsMaximum) }
        }
        return decode(data)
    }

    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 600
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

private final class PhotoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
