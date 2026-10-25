import GooglePlacesSwift
import MapKit
import SwiftUI

/// Google's rendered UI Kit can be shown alongside Apple Maps. Do not extract its photo URLs.
struct GooglePlaceCard: View {
    let item: MKMapItem
    var isActive = true
    var expanded = false
    @ScaledMetric(relativeTo: .body) private var compactHeight: CGFloat = 180
    @ScaledMetric(relativeTo: .body) private var expandedHeight: CGFloat = 320

    var body: some View {
        let query = GooglePlaceQuery(item: item)
        Group {
            if GooglePlacesService.isConfigured && query.isValid {
                if isActive {
                    GooglePlaceSearchCard(query: query, expanded: expanded)
                        .id(query)
                        .frame(height: expanded ? expandedHeight : compactHeight)
                } else {
                    PhotoPlaceholder(symbol: MapHomeView.symbol(for: item))
                        .frame(height: expanded ? expandedHeight : compactHeight)
                }
            } else {
                PhotoPlaceholder(symbol: MapHomeView.symbol(for: item))
                    .frame(height: 100)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GooglePlaceSearchCard: View {
    let query: GooglePlaceQuery
    let expanded: Bool
    @State private var request: PlaceSearchViewRequest
    @State private var failed = false
    @State private var empty = false
    @State private var retryID = 0

    init(query: GooglePlaceQuery, expanded: Bool) {
        self.query = query
        self.expanded = expanded
        _request = State(initialValue: .searchByText(query.request))
    }

    private var configuration: PlaceSearchConfiguration {
        var theme = PlacesMaterialTheme()
        theme.color.surface = MeshinowaTheme.card
        theme.color.primary = MeshinowaTheme.green
        theme.shape.cornerRadius = 14
        return PlaceSearchConfiguration(
            content: [.media(size: expanded ? .large : .small), .address()],
            preferTruncation: false, theme: theme,
            attributionPosition: .top, selectable: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if failed {
                HStack {
                    Text("店舗写真を読み込めませんでした")
                        .font(MeshinowaFont.text(13))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                    Spacer()
                    Button("再試行") { failed = false; retryID += 1 }
                        .font(MeshinowaFont.text(13, weight: .bold))
                        .frame(minHeight: 44)
                }
            } else if empty {
                PhotoPlaceholder().frame(height: 100)
            } else {
                // Keep Google's place name, attribution, photo authors and links intact.
                // The SDK owns requests/rendering; this app does not cache provider content.
                PlaceSearchView(orientation: .vertical, request: $request, configuration: configuration)
                    .onLoad { places in empty = places.isEmpty }
                    .onRequestError { _ in failed = true }
                    .id(retryID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
