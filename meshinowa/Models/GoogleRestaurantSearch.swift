import Combine
import GooglePlacesSwift
import MapKit
import ObjectiveC

private var providerDetailsKey: UInt8 = 0

/// Runtime provider data stays with the result. Photos and photo references are never persisted.
final class GoogleRestaurantDetails: NSObject {
    let placeID: String
    let place: Place?
    init(placeID: String, place: Place? = nil) { self.placeID = placeID; self.place = place }
}

extension MKMapItem {
    var googleDetails: GoogleRestaurantDetails? {
        get { objc_getAssociatedObject(self, &providerDetailsKey) as? GoogleRestaurantDetails }
        set { objc_setAssociatedObject(self, &providerDetailsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

@MainActor
enum GoogleRestaurantSearch {
    static let properties: [PlaceProperty] = [.placeID, .displayName, .coordinate, .formattedAddress, .types]

    static func category(types: Set<PlaceType>) -> MKPointOfInterestCategory? {
        if types.contains(.bakery) { return .bakery }
        if types.contains(.cafe) || types.contains(PlaceType(rawValue: "coffee_shop")) { return .cafe }
        if types.contains(.restaurant) || types.contains(PlaceType(rawValue: "food")) { return .restaurant }
        return nil
    }

    static func mapItem(_ place: Place) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.location,
                                                  addressDictionary: ["Street": place.formattedAddress ?? ""]))
        item.name = place.displayName
        item.pointOfInterestCategory = category(types: place.types)
        if let id = place.placeID { item.googleDetails = GoogleRestaurantDetails(placeID: id, place: place) }
        return item
    }

    static func request(term: String, region: MKCoordinateRegion, genre: RestaurantGenre,
                        nearby: Bool) -> SearchByTextRequest {
        // カフェとパンは種類で絞る。ほかのジャンルは飲食店の中から言葉で探し、結果をジャンルの判定で絞る。
        let types: [RestaurantGenre: PlaceType] = [.cafe: .cafe, .bakery: .bakery]
        let includedType: PlaceType? = genre == .all ? nil : (types[genre] ?? .restaurant)
        let radius = min(50_000, max(100, region.span.latitudeDelta * 111_320 / 2))
        let bias = CircularCoordinateRegion(center: region.center, radius: radius)
        if nearby, let rectangle = RectangularCoordinateRegion(
            northEast: CLLocationCoordinate2D(latitude: min(85, region.center.latitude + region.span.latitudeDelta / 2),
                                               longitude: min(180, region.center.longitude + region.span.longitudeDelta / 2)),
            southWest: CLLocationCoordinate2D(latitude: max(-85, region.center.latitude - region.span.latitudeDelta / 2),
                                               longitude: max(-180, region.center.longitude - region.span.longitudeDelta / 2))) {
            return SearchByTextRequest(textQuery: term, placeProperties: properties,
                                       locationRestriction: rectangle, includedType: includedType, maxResultCount: 20,
                                       isOpenNow: false, rankPreference: .relevance, regionCode: "JP",
                                       isStrictTypeFiltering: genre != .all)
        }
        return SearchByTextRequest(textQuery: term, placeProperties: properties, locationBias: bias,
                                   includedType: includedType, maxResultCount: 20, isOpenNow: false,
                                   rankPreference: .relevance, regionCode: "JP", isStrictTypeFiltering: genre != .all)
    }

    static func search(term: String, region: MKCoordinateRegion, genre: RestaurantGenre,
                       nearby: Bool) async throws -> [MKMapItem] {
        guard GooglePlacesService.isConfigured else { throw URLError(.userAuthenticationRequired) }
        let response = try await PlacesClient.shared.responseForSearchByText(
            with: request(term: term, region: region, genre: genre, nearby: nearby)).get()
        let items = (response.places ?? []).map(mapItem).filter { $0.pointOfInterestCategory != nil }
        guard let wanted = genre.foodGenre else { return items }
        // ジャンルで探して見つかったのに、店名や種類からはジャンルが分からないお店は、探したジャンルとして扱う。
        for item in items where item.foodGenre == .other { item.searchedFoodGenre = wanted }
        return items.filter { genre.matches($0) }
    }
}

/// 同じ画面で同じ条件を続けて求めたときは、表示中の結果または進行中の検索を共有する。
/// 保存するのは今の検索1件だけで、別の条件に移ったら破棄する。端末には永続保存しない。
@MainActor
final class RestaurantSearchSession: ObservableObject {
    typealias Loader = (String, MKCoordinateRegion, RestaurantGenre, Bool) async throws -> [MKMapItem]
    private struct Key: Equatable {
        let term: String
        let genre: RestaurantGenre
        let nearby: Bool
        let region: [Double]

        init(term: String, region: MKCoordinateRegion, genre: RestaurantGenre, nearby: Bool) {
            self.term = term.trimmingCharacters(in: .whitespacesAndNewlines)
            self.genre = genre
            self.nearby = nearby
            // カメラ停止時のごく小さい揺れを同じ範囲として扱う（約10m単位）。
            self.region = [region.center.latitude, region.center.longitude, region.span.latitudeDelta, region.span.longitudeDelta]
                .map { ($0 * 10_000).rounded() }
        }
    }
    private struct Pending {
        let id: UUID
        let key: Key
        let task: Task<[MKMapItem], Error>
    }
    private let loader: Loader
    private var pending: Pending?
    private var currentID: UUID?
    private var displayedKey: Key?
    private var displayedResults: [MKMapItem] = []

    init(loader: Loader? = nil) {
        self.loader = loader ?? { term, region, genre, nearby in
            try await GoogleRestaurantSearch.search(term: term, region: region, genre: genre, nearby: nearby)
        }
    }

    func search(term: String, region: MKCoordinateRegion, genre: RestaurantGenre, nearby: Bool,
                force: Bool = false) async throws -> [MKMapItem] {
        let key = Key(term: term, region: region, genre: genre, nearby: nearby)
        if !force && key == displayedKey { return displayedResults }
        let operation: Pending
        if let pending, pending.key == key {
            operation = pending
        } else {
            pending?.task.cancel()
            displayedKey = nil
            displayedResults = []
            let task = Task { try await loader(term, region, genre, nearby) }
            operation = Pending(id: UUID(), key: key, task: task)
            currentID = operation.id
            pending = operation
        }
        defer { if pending?.id == operation.id { pending = nil } }
        let results = try await operation.task.value
        guard currentID == operation.id else { throw CancellationError() }
        displayedKey = key
        displayedResults = results
        return results
    }
}
