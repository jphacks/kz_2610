import Foundation
import MapKit

/// 以前の「行きたい／行った」の保存形式。読み込み時の移行にだけ使う。
private enum LegacyVisitStatus: String, Codable { case wantToGo, visited }

struct SavedRestaurant: Codable, Identifiable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let category: String?
    let phoneNumber: String?
    let googlePlaceID: String?
    let savedAt: Date
    /// いいね（保存して行きたい）。行ったかどうかはレビューがあるかで決まり、ここには持たない。
    var isLiked: Bool

    init(item: MKMapItem, savedAt: Date = .now, isLiked: Bool = true) {
        id = Self.identifier(for: item)
        name = item.name ?? "飲食店"
        address = item.placemark.title ?? "住所の情報がありません"
        latitude = item.placemark.coordinate.latitude
        longitude = item.placemark.coordinate.longitude
        category = item.pointOfInterestCategory?.rawValue
        phoneNumber = item.phoneNumber
        googlePlaceID = item.googleDetails?.placeID
        self.savedAt = savedAt
        self.isLiked = isLiked
    }

    enum CodingKeys: String, CodingKey {
        case id, name, address, latitude, longitude, category, phoneNumber, savedAt, isLiked, isVisited
        // 以前の形式のキー。
        case status, isFavorite, googlePlaceID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decode(String.self, forKey: .address)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        phoneNumber = try c.decodeIfPresent(String.self, forKey: .phoneNumber)
        googlePlaceID = try c.decodeIfPresent(String.self, forKey: .googlePlaceID)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        if c.contains(.isLiked) || c.contains(.isVisited) {
            // 「行った」だけが付いていたお店は、記録を失わないようにいいねへ移す。
            isLiked = try (c.decodeIfPresent(Bool.self, forKey: .isLiked) ?? false)
                || (c.decodeIfPresent(Bool.self, forKey: .isVisited) ?? false)
        } else {
            // 以前の形式：行きたい・お気に入り・行った（状態のない最初期のデータも含む）は、いいねにまとめる。
            let status = c.contains(.status) ? try c.decodeIfPresent(LegacyVisitStatus.self, forKey: .status) : .wantToGo
            let isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
            isLiked = status != nil || isFavorite
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(address, forKey: .address)
        try c.encode(latitude, forKey: .latitude); try c.encode(longitude, forKey: .longitude)
        try c.encodeIfPresent(category, forKey: .category); try c.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try c.encodeIfPresent(googlePlaceID, forKey: .googlePlaceID)
        try c.encode(savedAt, forKey: .savedAt)
        try c.encode(isLiked, forKey: .isLiked)
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
        item.searchedFoodGenre = PresentationDemo.foodGenreHint(for: id)
        item.phoneNumber = phoneNumber
        item.pointOfInterestCategory = category.map(MKPointOfInterestCategory.init(rawValue:))
        if let googlePlaceID { item.googleDetails = GoogleRestaurantDetails(placeID: googlePlaceID) }
        return item
    }
}
