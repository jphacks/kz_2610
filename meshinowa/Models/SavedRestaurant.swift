import Foundation
import MapKit

struct SavedRestaurant: Codable, Identifiable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let category: String?
    let phoneNumber: String?
    let savedAt: Date

    init(item: MKMapItem, savedAt: Date = .now) {
        id = Self.identifier(for: item)
        name = item.name ?? "飲食店"
        address = item.placemark.title ?? "住所の情報がありません"
        latitude = item.placemark.coordinate.latitude
        longitude = item.placemark.coordinate.longitude
        category = item.pointOfInterestCategory?.rawValue
        phoneNumber = item.phoneNumber
        self.savedAt = savedAt
    }

    /// iOS 17でも再検索した店を照合できるよう、店名と約10m単位の座標を使う。
    static func identifier(for item: MKMapItem) -> String {
        let name = (item.name ?? "飲食店")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
        let coordinate = item.placemark.coordinate
        return "\(name)|\(Int((coordinate.latitude * 10_000).rounded()))|\(Int((coordinate.longitude * 10_000).rounded()))"
    }

    var mapItem: MKMapItem {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: ["Street": address])
        let item = MKMapItem(placemark: placemark)
        item.name = name
        item.phoneNumber = phoneNumber
        item.pointOfInterestCategory = category.map(MKPointOfInterestCategory.init(rawValue:))
        return item
    }
}
