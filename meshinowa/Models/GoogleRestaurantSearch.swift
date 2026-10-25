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
        let types: [RestaurantGenre: PlaceType] = [.restaurant: .restaurant, .cafe: .cafe, .bakery: .bakery]
        let radius = min(50_000, max(100, region.span.latitudeDelta * 111_320 / 2))
        let bias = CircularCoordinateRegion(center: region.center, radius: radius)
        if nearby, let rectangle = RectangularCoordinateRegion(
            northEast: CLLocationCoordinate2D(latitude: min(85, region.center.latitude + region.span.latitudeDelta / 2),
                                               longitude: min(180, region.center.longitude + region.span.longitudeDelta / 2)),
            southWest: CLLocationCoordinate2D(latitude: max(-85, region.center.latitude - region.span.latitudeDelta / 2),
                                               longitude: max(-180, region.center.longitude - region.span.longitudeDelta / 2))) {
            return SearchByTextRequest(textQuery: term, placeProperties: properties,
                                       locationRestriction: rectangle, includedType: types[genre], maxResultCount: 20,
                                       isOpenNow: false, rankPreference: .relevance, regionCode: "JP",
                                       isStrictTypeFiltering: genre != .all)
        }
        return SearchByTextRequest(textQuery: term, placeProperties: properties, locationBias: bias,
                                   includedType: types[genre], maxResultCount: 20, isOpenNow: false,
                                   rankPreference: .relevance, regionCode: "JP", isStrictTypeFiltering: genre != .all)
    }

    static func search(term: String, region: MKCoordinateRegion, genre: RestaurantGenre,
                       nearby: Bool) async throws -> [MKMapItem] {
        guard GooglePlacesService.isConfigured else { throw URLError(.userAuthenticationRequired) }
        let response = try await PlacesClient.shared.responseForSearchByText(
            with: request(term: term, region: region, genre: genre, nearby: nearby)).get()
        return (response.places ?? []).map(mapItem).filter {
            $0.pointOfInterestCategory != nil && genre.matches($0)
        }
    }
}
