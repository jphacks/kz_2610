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
