import Combine
import GooglePlacesSwift
import MapKit
import UIKit

struct LoadedRestaurantPhoto {
    let image: UIImage
    var metadata: Photo?
    var placeAttributions: AttributedString?
}

/// Short-lived display-session reuse only. Persistent HTTP caching remains owned by the SDK.
@MainActor
final class RestaurantPhotoStore: ObservableObject {
    @Published private(set) var revision = 0
    static let shared = RestaurantPhotoStore()
    typealias Loader = (MKMapItem) async throws -> LoadedRestaurantPhoto?

    private final class Entry: NSObject {
        let photo: LoadedRestaurantPhoto?
        let expires: Date
        init(_ photo: LoadedRestaurantPhoto?, expires: Date) { self.photo = photo; self.expires = expires }
    }
    private struct Waiter {
        let foreground: Bool
        let continuation: CheckedContinuation<Void, Never>
    }
    private let cache = NSCache<NSString, Entry>()
    private var inFlight: [String: Task<LoadedRestaurantPhoto?, Error>] = [:]
    private var active = 0
    private var waiters: [Waiter] = []
    private let loader: Loader
    private let now: () -> Date
    private var memoryObserver: NSObjectProtocol?

    init(now: @escaping () -> Date = Date.init, loader: Loader? = nil) {
        self.now = now
        self.loader = loader ?? Self.fetch
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 24
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cache.removeAllObjects()
                self?.revision &+= 1
            }
        }
    }

    deinit {
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
    }

    private func key(_ item: MKMapItem) -> String {
        item.googleDetails?.placeID ?? "legacy:" + SavedRestaurant.identifier(for: item)
    }

    private func entry(for item: MKMapItem) -> Entry? {
        let key = key(item) as NSString
        guard let entry = cache.object(forKey: key) else { return nil }
        guard entry.expires > now() else { cache.removeObject(forKey: key); return nil }
        return entry
    }

    /// Synchronous lookup avoids a placeholder flash when returning from another screen.
    func cachedPhoto(for item: MKMapItem) -> LoadedRestaurantPhoto? { entry(for: item)?.photo }

    func photo(for item: MKMapItem, foreground: Bool = true) async throws -> LoadedRestaurantPhoto? {
        if let entry = entry(for: item) { return entry.photo }
        let requestKey = key(item)
        if let task = inFlight[requestKey] { return try await task.value }
        // The shared request survives a recycled carousel view and serves every waiter.
        let task = Task(priority: foreground ? .userInitiated : .utility) { [self] in
            await acquireSlot(foreground: foreground)
            defer { releaseSlot(); inFlight.removeValue(forKey: requestKey) }
            let photo = try await loader(item)
            let cost = photo.map { ($0.image.cgImage?.bytesPerRow ?? 0) * ($0.image.cgImage?.height ?? 0) } ?? 0
            let entry = Entry(photo, expires: now().addingTimeInterval(photo == nil ? 30 : 120))
            cache.setObject(entry, forKey: requestKey as NSString, cost: cost)
            // Legacy store resolution can discover a Google ID during the request.
            if key(item) != requestKey { cache.setObject(entry, forKey: key(item) as NSString, cost: cost) }
            revision &+= 1
            return photo
        }
        inFlight[requestKey] = task
        return try await task.value
    }

    private func acquireSlot(foreground: Bool) async {
        if active < 3 { active += 1; return }
        await withCheckedContinuation { waiters.append(Waiter(foreground: foreground, continuation: $0)) }
    }

    private func releaseSlot() {
        guard !waiters.isEmpty else { active -= 1; return }
        let next = waiters.firstIndex(where: \.foreground) ?? 0
        waiters.remove(at: next).continuation.resume()
    }

    /// Load the selected photo first, then only the two adjacent stores, including loop boundaries.
    func prepareCarousel(items: [MKMapItem], selectedIndex: Int) async {
        guard items.indices.contains(selectedIndex) else { return }
        _ = try? await photo(for: items[selectedIndex])
        guard !Task.isCancelled, items.count > 1 else { return }
        let previous = (selectedIndex - 1 + items.count) % items.count
        let next = (selectedIndex + 1) % items.count
        async let before = photo(for: items[previous], foreground: false)
        if next != previous { _ = try? await photo(for: items[next], foreground: false) }
        _ = try? await before
    }

    private static func fetch(_ item: MKMapItem) async throws -> LoadedRestaurantPhoto? {
        guard GooglePlacesService.isConfigured else { return nil }
        let place: Place
        if let id = item.googleDetails?.placeID {
            place = try await PlacesClient.shared.fetchPlace(with: FetchPlaceRequest(
                placeID: id, placeProperties: [.placeID, .photos])).get()
        } else {
            let query = GooglePlaceQuery(item: item)
            guard query.isValid else { return nil }
            let response = try await PlacesClient.shared.responseForSearchByText(with: query.request).get()
            guard let match = response.places?.first,
                  CLLocation(latitude: match.location.latitude, longitude: match.location.longitude)
                    .distance(from: CLLocation(latitude: query.latitude, longitude: query.longitude)) < 300 else { return nil }
            place = match
            if let id = match.placeID { item.googleDetails = GoogleRestaurantDetails(placeID: id) }
        }
        guard let first = place.photos?.first else { return nil }
        let image = try await PlacesClient.shared.fetchPhoto(with: FetchPhotoRequest(
            photo: first, maxSize: CGSize(width: 1000, height: 700))).get()
        let prepared = await image.byPreparingForDisplay() ?? image
        return LoadedRestaurantPhoto(image: prepared, metadata: first, placeAttributions: place.attributions)
    }
}
