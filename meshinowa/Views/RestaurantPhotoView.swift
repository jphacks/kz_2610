import GooglePlacesSwift
import MapKit
import SwiftUI

/// A custom photo surface, not a Google UI Kit widget. Retains required photo credits.
struct RestaurantPhotoView: View {
    let item: MKMapItem
    var isActive = true
    var expanded = false
    var showsGoogleAttribution = true
    @State private var photo: UIImage?
    @State private var metadata: Photo?
    @State private var placeAttributions: AttributedString?
    @State private var failed = false
    @State private var loading = false
    @State private var retry = 0

    private var identity: String { item.googleDetails?.placeID ?? SavedRestaurant.identifier(for: item) }

    /// The SDK can return the same linked credit in both fields. Display it once.
    private func needsSeparateCredit(_ author: AuthorAttribution) -> Bool {
        guard let credits = metadata?.attributions else { return true }
        return !credits.runs.contains { run in
            String(credits[run.range].characters).contains(author.displayName)
                && run.link == author.url
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        PhotoPlaceholder(symbol: MapHomeView.symbol(for: item))
                            .overlay {
                                if loading { ProgressView().tint(MeshinowaTheme.green) }
                            }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .frame(height: expanded ? 230 : 140)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(photo == nil ? "店舗写真なし" : "店舗写真")

            if photo != nil {
                // Google attribution is required on detail/list screens without a visible Google map.
                HStack(alignment: .top, spacing: 6) {
                    if showsGoogleAttribution { Text("Google Maps").font(.system(size: 12)) }
                    Spacer(minLength: 0)
                    if let credits = metadata?.attributions { Text(credits).font(.system(size: 11)) }
                }
                if let credits = placeAttributions { Text(credits).font(.system(size: 11)) }
                if let metadata {
                    ForEach(Array(metadata.authorAttributions.filter(needsSeparateCredit).enumerated()), id: \.offset) { _, author in
                        if let url = author.url {
                            Link("写真：" + author.displayName, destination: url)
                                .font(.system(size: 11)).tint(MeshinowaTheme.green)
                        } else {
                            Text("写真：" + author.displayName).font(.system(size: 11))
                        }
                    }
                }
            } else if failed {
                Button("写真を再読み込み") { retry += 1 }
                    .font(MeshinowaFont.text(12)).frame(minHeight: 44)
            }
        }
        .foregroundStyle(MeshinowaTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(identity)|\(isActive)|\(retry)") {
            guard isActive, photo == nil, GooglePlacesService.isConfigured else { return }
            loading = true
            failed = false
            defer { loading = false }
            do {
                let place: Place
                if let id = item.googleDetails?.placeID {
                    place = try await PlacesClient.shared.fetchPlace(with: FetchPlaceRequest(
                        placeID: id, placeProperties: [.placeID, .photos])).get()
                } else {
                    let query = GooglePlaceQuery(item: item)
                    guard query.isValid else { return }
                    let response = try await PlacesClient.shared.responseForSearchByText(with: query.request).get()
                    guard let match = response.places?.first,
                          CLLocation(latitude: match.location.latitude, longitude: match.location.longitude)
                            .distance(from: CLLocation(latitude: query.latitude, longitude: query.longitude)) < 300 else { return }
                    place = match
                    if let id = match.placeID { item.googleDetails = GoogleRestaurantDetails(placeID: id) }
                }
                try Task.checkCancellation()
                guard let first = place.photos?.first else { return }
                let image = try await PlacesClient.shared.fetchPhoto(with: FetchPhotoRequest(
                    photo: first, maxSize: CGSize(width: 1000, height: 700))).get()
                try Task.checkCancellation()
                metadata = first
                placeAttributions = place.attributions
                photo = image
            } catch is CancellationError {
                // Disappeared/recycled cards must not show a late response from another store.
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}
