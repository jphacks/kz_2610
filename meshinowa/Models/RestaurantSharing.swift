import MapKit

/// 外部共有には、自分で選んだ内容とお店の場所だけを渡す。
enum RestaurantSharing {
    static func mapURL(for item: MKMapItem) -> URL {
        var url = URLComponents(string: "https://www.google.com/maps/search/")!
        let point = item.placemark.coordinate
        url.queryItems = [URLQueryItem(name: "api", value: "1"),
                          URLQueryItem(name: "query", value: "\(point.latitude),\(point.longitude)")]
        if let placeID = item.googleDetails?.placeID {
            url.queryItems?.append(URLQueryItem(name: "query_place_id", value: placeID))
        }
        return url.url!
    }

    static func message(for item: MKMapItem, invitation: Bool = false) -> String {
        "\(invitation ? "ここ今度行かない？" : "このお店、おすすめです")\n\(item.name ?? "飲食店")\n\(mapURL(for: item).absoluteString)"
    }

    /// 番地や建物名を共有画像に載せない。町名を判断できなければ市区町村までにする。
    static func area(for item: MKMapItem) -> String {
        let place = item.placemark
        return [place.locality, place.subLocality].compactMap { $0 }.filter { !$0.isEmpty }.joined()
    }
}
