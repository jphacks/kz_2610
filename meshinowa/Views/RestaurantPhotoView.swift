import MapKit
import SwiftUI

/// Known photos are rendered immediately from the shared cache, including on detail sheets.
struct RestaurantPhotoView: View {
    let query: RestaurantPhotoQuery
    var symbol: String
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat
    private let store: RestaurantPhotoStore
    private struct Loaded {
        let query: RestaurantPhotoQuery
        let asset: RestaurantPhotoAsset?
    }
    @State private var loaded: Loaded
    private var asset: RestaurantPhotoAsset? {
        loaded.query == query ? loaded.asset : store.cached(for: query)
    }
    @Environment(\.scenePhase) private var scenePhase

    init(item: MKMapItem, width: CGFloat? = nil, height: CGFloat = 150, cornerRadius: CGFloat = 14,
         store: RestaurantPhotoStore? = nil) {
        let query = RestaurantPhotoQuery(item: item)
        self.query = query
        self.symbol = MapHomeView.symbol(for: item)
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        let photoStore = store ?? .shared
        self.store = photoStore
        _loaded = State(initialValue: Loaded(query: query, asset: photoStore.cached(for: query)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                PhotoPlaceholder(symbol: symbol, cornerRadius: cornerRadius)
                if let asset {
                    Image(uiImage: asset.image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("\(asset.photo.name)の店舗写真")
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            Text("画像提供：ホットペッパー グルメ")
                .font(MeshinowaFont.text(11, relativeTo: .caption2))
                .foregroundStyle(MeshinowaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(asset == nil ? 0 : 1)
                .accessibilityHidden(asset == nil)
            if let asset {
                if width == nil {
                    Link("ホットペッパーグルメでお店を見る", destination: asset.photo.shopUrl)
                        .font(MeshinowaFont.text(13, weight: .bold))
                        .foregroundStyle(MeshinowaTheme.green)
                        .frame(minHeight: 44)
                    HotPepperServiceCredit()
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .task(id: RefreshID(query: query, active: scenePhase == .active)) {
            if scenePhase == .active { await refresh() }
        }
    }

    private struct RefreshID: Equatable {
        let query: RestaurantPhotoQuery
        let active: Bool
    }

    private func refresh() async {
        loaded = Loaded(query: query, asset: store.cached(for: query))
        while !Task.isCancelled {
            let result = await store.asset(for: query)
            guard !Task.isCancelled else { return }
            loaded = Loaded(query: query, asset: result)
            // Revalidate at expiry while a view remains visible.
            do { try await Task.sleep(for: .seconds(store.refreshInterval(for: query))) }
            catch { return }
        }
    }
}

struct HotPepperServiceCredit: View {
    var body: some View {
        Link("Powered by ホットペッパーグルメ Webサービス", destination: URL(string: "https://webservice.recruit.co.jp/")!)
            .font(MeshinowaFont.text(11, relativeTo: .caption2))
            .foregroundStyle(MeshinowaTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44, alignment: .leading)
    }
}
