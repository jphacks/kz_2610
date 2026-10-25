import GoogleMaps
import MapKit
import SwiftUI

/// A camera command, separate from camera observations so gestures never reset the map.
struct GoogleMapPosition {
    let id = UUID()
    var region: MKCoordinateRegion?
    var camera: GMSCameraPosition?
    var coordinates: [CLLocationCoordinate2D] = []

    static func region(_ region: MKCoordinateRegion) -> Self { Self(region: region) }
    static func camera(_ camera: GMSCameraPosition) -> Self { Self(camera: camera) }
    static func fit(_ coordinates: [CLLocationCoordinate2D]) -> Self { Self(coordinates: coordinates) }
}

struct GoogleMapPin {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    var symbol = "fork.knife"
    /// ピンの器の形を決めるジャンル。
    var genre: FoodGenre = .other
    var mark: PlacePin.Mark = .none
    var showsLikeBadge = false
    var scoreTag: String?
    var scoreTitle: String?
}

struct GoogleMapCanvas: View {
    let position: GoogleMapPosition
    let pins: [GoogleMapPin]
    @Binding var selectedID: String?
    var topPadding: CGFloat = 0
    var bottomPadding: CGFloat = 0
    var onCameraEnd: ((MKCoordinateRegion, GMSCameraPosition) -> Void)?

    var body: some View {
        if GooglePlacesService.isMapConfigured {
            GoogleMapRepresentable(position: position, pins: pins, selectedID: $selectedID,
                                   topPadding: topPadding, bottomPadding: bottomPadding, onCameraEnd: onCameraEnd)
        } else {
            ContentUnavailableView("地図を表示できません", systemImage: "map", description: Text("Google Mapsの設定を確認してください。"))
        }
    }
}

private struct GoogleMapRepresentable: UIViewRepresentable {
    let position: GoogleMapPosition
    let pins: [GoogleMapPin]
    @Binding var selectedID: String?
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let onCameraEnd: ((MKCoordinateRegion, GMSCameraPosition) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(latitude: 35.6812, longitude: 139.7671, zoom: 15)
        let map = GMSMapView(options: options)
        map.delegate = context.coordinator
        map.accessibilityElementsHidden = false
        map.settings.rotateGestures = false
        map.settings.tiltGestures = false
        map.settings.compassButton = true
        map.isBuildingsEnabled = false
        map.isMyLocationEnabled = true
        // App markers remain selectable without unrelated built-in POI pins.
        map.mapStyle = try? GMSMapStyle(jsonString: "[{\"featureType\":\"poi\",\"elementType\":\"labels\",\"stylers\":[{\"visibility\":\"off\"}]}]")
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        map.padding = UIEdgeInsets(top: topPadding, left: 0, bottom: bottomPadding, right: 0)
        coordinator.updatePins(map)
        guard coordinator.positionID != position.id else { return }
        coordinator.positionID = position.id
        if let camera = position.camera {
            map.animate(to: camera)
        } else {
            var bounds: GMSCoordinateBounds?
            if let region = position.region {
                bounds = GMSCoordinateBounds(
                    coordinate: CLLocationCoordinate2D(latitude: min(85, region.center.latitude + region.span.latitudeDelta / 2),
                                                       longitude: region.center.longitude + region.span.longitudeDelta / 2),
                    coordinate: CLLocationCoordinate2D(latitude: max(-85, region.center.latitude - region.span.latitudeDelta / 2),
                                                       longitude: region.center.longitude - region.span.longitudeDelta / 2))
            } else if let first = position.coordinates.first {
                bounds = position.coordinates.dropFirst().reduce(GMSCoordinateBounds(coordinate: first, coordinate: first)) { $0.includingCoordinate($1) }
            }
            if let bounds {
                map.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 40))
            }
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapRepresentable
        var positionID: UUID?
        private var markers: [String: GMSMarker] = [:]
        private var signatures: [String: String] = [:]
        init(_ parent: GoogleMapRepresentable) { self.parent = parent }

        @MainActor func updatePins(_ map: GMSMapView) {
            let ids = Set(parent.pins.map(\.id))
            for id in Array(markers.keys) where !ids.contains(id) {
                markers.removeValue(forKey: id)?.map = nil
                signatures.removeValue(forKey: id)
            }
            for (index, pin) in parent.pins.enumerated() {
                let marker = markers[pin.id] ?? GMSMarker(position: pin.coordinate)
                let selected = pin.id == parent.selectedID
                marker.position = pin.coordinate
                marker.title = pin.title
                marker.userData = pin.id
                marker.zIndex = selected ? 1000 : Int32(index)
                marker.groundAnchor = CGPoint(x: 0.5, y: 1)
                let signature = "\(pin.genre.rawValue)|\(pin.symbol)|\(pin.mark)|\(pin.showsLikeBadge)|\(selected)|\(pin.scoreTitle ?? "")|\(pin.scoreTag ?? "")"
                if signatures[pin.id] != signature {
                    let content: AnyView
                    if let title = pin.scoreTitle {
                        content = AnyView(ScorePin(title: title, tag: pin.scoreTag, isSelected: selected))
                    } else {
                        content = AnyView(PlacePin(symbol: pin.symbol, genre: pin.genre, mark: pin.mark,
                                                  showsLikeBadge: pin.showsLikeBadge, isSelected: selected))
                    }
                    let renderer = ImageRenderer(content: content.padding(8).environment(\.colorScheme, .light))
                    renderer.scale = UIScreen.main.scale
                    marker.icon = renderer.uiImage
                    signatures[pin.id] = signature
                }
                if marker.map == nil { marker.map = map }
                markers[pin.id] = marker
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let id = marker.userData as? String else { return false }
            parent.selectedID = id
            return true
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            let visible = mapView.projection.visibleRegion()
            let bounds = GMSCoordinateBounds(region: visible)
            let longitudeDelta = (bounds.northEast.longitude - bounds.southWest.longitude + 360).truncatingRemainder(dividingBy: 360)
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (bounds.northEast.latitude + bounds.southWest.latitude) / 2,
                                               longitude: bounds.southWest.longitude + longitudeDelta / 2),
                span: MKCoordinateSpan(latitudeDelta: max(0.00001, bounds.northEast.latitude - bounds.southWest.latitude),
                                       longitudeDelta: max(0.00001, longitudeDelta)))
            parent.onCameraEnd?(region, position)
        }
    }
}
