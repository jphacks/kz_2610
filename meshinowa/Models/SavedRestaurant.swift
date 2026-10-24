import Foundation
import MapKit

enum VisitStatus: String, Codable { case wantToGo, visited }

struct SavedRestaurant: Codable, Identifiable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let category: String?
    let phoneNumber: String?
    let savedAt: Date
    var status: VisitStatus?
    var isFavorite: Bool

    init(item: MKMapItem, savedAt: Date = .now, status: VisitStatus? = .wantToGo, isFavorite: Bool = false) {
        id = Self.identifier(for: item)
        name = item.name ?? "飲食店"
        address = item.placemark.title ?? "住所の情報がありません"
        latitude = item.placemark.coordinate.latitude
        longitude = item.placemark.coordinate.longitude
        category = item.pointOfInterestCategory?.rawValue
        phoneNumber = item.phoneNumber
        self.savedAt = savedAt
        self.status = status
        self.isFavorite = isFavorite
    }

    enum CodingKeys: String, CodingKey { case id, name, address, latitude, longitude, category, phoneNumber, savedAt, status, isFavorite }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decode(String.self, forKey: .address)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        phoneNumber = try c.decodeIfPresent(String.self, forKey: .phoneNumber)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        status = c.contains(.status) ? try c.decodeIfPresent(VisitStatus.self, forKey: .status) : .wantToGo
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(address, forKey: .address)
        try c.encode(latitude, forKey: .latitude); try c.encode(longitude, forKey: .longitude)
        try c.encodeIfPresent(category, forKey: .category); try c.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try c.encode(savedAt, forKey: .savedAt)
        // nilも明示して、古い「行きたい」データとの区別を保つ。
        try c.encode(status, forKey: .status)
        try c.encode(isFavorite, forKey: .isFavorite)
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
