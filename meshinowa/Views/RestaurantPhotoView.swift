import GooglePlacesSwift
import MapKit
import SwiftUI

/// A custom photo surface, not a Google UI Kit widget. Retains required photo credits.
struct RestaurantPhotoView: View {
    let item: MKMapItem
    var isActive = true
    var expanded = false
    var showsGoogleAttribution = true
    var imageHeight: CGFloat? = nil
    var overlaysCredits = false
    @ObservedObject private var store = RestaurantPhotoStore.shared
    @State private var loaded: LoadedRestaurantPhoto?

    private var current: LoadedRestaurantPhoto? { loaded ?? store.cachedPhoto(for: item) }
    private var photo: UIImage? { current?.image }
    private var metadata: Photo? { current?.metadata }
    private var placeAttributions: AttributedString? { current?.placeAttributions }
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
                        FoodGenreMark(genre: item.foodGenre, size: expanded ? 72 : 48)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(MeshinowaTheme.photo)
                            .overlay {
                                if loading { ProgressView().tint(MeshinowaTheme.green) }
                            }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .frame(height: imageHeight ?? (expanded ? 230 : 140))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(photo == nil ? "店舗写真なし" : "店舗写真")
            .overlay(alignment: .bottom) {
                if photo != nil && overlaysCredits {
                    credits
                        .foregroundStyle(MeshinowaTheme.paper)
                        .tint(MeshinowaTheme.paper)
                        .padding(8)
                        .padding(.top, 12)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
                }
            }

            if photo != nil && !overlaysCredits {
                credits
            } else if failed {
                Button("写真を再読み込み") { retry += 1 }
                    .font(MeshinowaFont.text(12)).frame(minHeight: 44)
            }
        }
        .foregroundStyle(MeshinowaTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(identity)|\(isActive)|\(retry)") {
            guard isActive, loaded == nil, GooglePlacesService.isConfigured else { return }
            loading = true
            failed = false
            defer { loading = false }
            do {
                let result = try await store.photo(for: item)
                try Task.checkCancellation()
                loaded = result
            } catch is CancellationError {
                // Disappeared/recycled cards must not show a late response from another store.
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 2) {
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
        }
    }

}
