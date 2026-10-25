import GooglePlacesSwift
import MapKit

/// Only public store identity is sent to Google Places; no account/review data or current location.
struct GooglePlaceQuery: Hashable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    init(item: MKMapItem) {
        let candidate = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let placemarkTitle = (item.placemark.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let street = (item.placemark.addressDictionary?["Street"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // MKMapItem can substitute its street address when no business name was supplied.
        name = [placemarkTitle, street].contains(candidate) ? "" : candidate
        address = (item.placemark.title ?? "").withoutPostalCode.replacingOccurrences(of: "\n", with: " ")
        latitude = item.placemark.coordinate.latitude
        longitude = item.placemark.coordinate.longitude
    }

    var isValid: Bool {
        !name.isEmpty && name.count <= 200 && address.count <= 500
            && latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    var request: SearchByTextRequest {
        SearchByTextRequest(
            textQuery: [name, address].filter { !$0.isEmpty }.joined(separator: " "),
            // Used only to resolve pre-migration saved stores without a Google place ID.
            placeProperties: [.placeID, .displayName, .coordinate, .photos],
            locationBias: CircularCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), radius: 300),
            maxResultCount: 1,
            isOpenNow: false,
            rankPreference: .relevance,
            regionCode: "JP"
        )
    }
}
