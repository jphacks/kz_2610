import GooglePlacesSwift
import MapKit
import SwiftUI

/// 既存アプリの方針（地図・店舗写真は Google Maps / Places）に合わせるためのアダプタ。
/// 既存の GoogleMapCanvas・RestaurantPhotoStore・GooglePlacesService は読むだけで、手を入れない。
enum SwipeGoogleMapsBridge {
    @MainActor static var isMapConfigured: Bool { GooglePlacesService.isMapConfigured }

    /// 店舗写真を取る関数。Google Places が未設定なら nil（星評価ビューだけを使う）。
    @MainActor
    static func placePhotoFetcher(mapItems: SwipeMapItemRegistry) -> SwipePlacePhotoCache.Fetcher? {
        guard GooglePlacesService.isConfigured else { return nil }
        return { candidate in
            let item = mapItems.item(for: candidate)
            guard let loaded = try? await RestaurantPhotoStore.shared.photo(for: item) else { return nil }
            return SwipePlacePhoto(image: loaded.image, credits: credits(for: loaded),
                                   shortCredit: shortCredit(for: loaded))
        }
    }

    private static func credits(for photo: LoadedRestaurantPhoto) -> AttributedString {
        var lines: [AttributedString] = [AttributedString("Google Maps")]
        if let attributions = photo.metadata?.attributions { lines.append(attributions) }
        if let place = photo.placeAttributions { lines.append(place) }
        for author in photo.metadata?.authorAttributions ?? [] {
            var line = AttributedString("写真：" + author.displayName)
            if let url = author.url { line.link = url }
            lines.append(line)
        }
        return lines.dropFirst().reduce(lines[0]) { $0 + AttributedString("\n") + $1 }
    }

    private static func shortCredit(for photo: LoadedRestaurantPhoto) -> String {
        let author = photo.metadata?.authorAttributions.first?.displayName
        return author.map { "Google Maps・写真：\($0)" } ?? "Google Maps"
    }
}

/// Google Maps の地図にお店のピンを1本立てる。小窓（操作なし）と大きな地図の両方で使う。
struct SwipeShopMapView: View {
    let candidate: SwipeCandidate
    var interactive = false
    @State private var position: GoogleMapPosition
    @State private var selectedID: String? = "shop"

    init(candidate: SwipeCandidate, interactive: Bool = false, spanMeters: Double = 450) {
        self.candidate = candidate
        self.interactive = interactive
        let center = CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude)
        _position = State(initialValue: .region(MKCoordinateRegion(center: center, latitudinalMeters: spanMeters,
                                                                    longitudinalMeters: spanMeters)))
    }

    var body: some View {
        if SwipeGoogleMapsBridge.isMapConfigured {
            GoogleMapCanvas(position: position, pins: [
                GoogleMapPin(id: "shop", title: candidate.name,
                             coordinate: CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude),
                             symbol: SwipeTheme.symbol(for: candidate.category),
                             genre: FoodGenre(rawValue: candidate.category == .pan ? "bread" : candidate.category.rawValue) ?? .other)
            ], selectedID: $selectedID)
            .allowsHitTesting(interactive)
        } else {
            // キー未設定でも小窓の形は保つ。
            ZStack {
                SwipeTheme.mapPlaceholder
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: interactive ? 40 : 22))
                    .foregroundStyle(SwipeTheme.brand)
            }
        }
    }
}
