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
    var showsPinNames = true
    var onUserMove: (() -> Void)?
    var onCameraEnd: ((MKCoordinateRegion, GMSCameraPosition) -> Void)?

    var body: some View {
        if GooglePlacesService.isMapConfigured {
            GoogleMapRepresentable(position: position, pins: pins, selectedID: $selectedID,
                                   topPadding: topPadding, bottomPadding: bottomPadding, showsPinNames: showsPinNames, onUserMove: onUserMove, onCameraEnd: onCameraEnd)
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
    let showsPinNames: Bool
    let onUserMove: (() -> Void)?
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
        map.mapStyle = (try? GMSMapStyle(jsonString: MeshinowaMapStyle.json))
            ?? (try? GMSMapStyle(jsonString: "[{\"featureType\":\"poi\",\"elementType\":\"labels\",\"stylers\":[{\"visibility\":\"off\"}]}]"))
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
            // すべてのピンの位置を先に確保し、名前が別のピンを覆わないようにする。
            let pinRects = Dictionary(parent.pins.map { pin in
                let point = map.projection.point(for: pin.coordinate)
                let size: CGFloat = pin.id == parent.selectedID ? 58 : 40
                return (pin.id, CGRect(x: point.x - size / 2, y: point.y - size, width: size, height: size))
            }, uniquingKeysWith: { first, _ in first })
            var labelRects: [CGRect] = []
            var namedIDs = Set<String>()
            if parent.showsPinNames && map.camera.zoom >= 15.5 {
                // 地図側は優先度が低い順に渡す。選択中は必ず先に判定する。
                let ordered = parent.pins.reversed().sorted {
                    ($0.id == parent.selectedID ? 1 : 0) > ($1.id == parent.selectedID ? 1 : 0)
                }
                for pin in ordered {
                    let point = map.projection.point(for: pin.coordinate)
                    let name = Self.shortName(pin.title)
                    let font = UIFont.systemFont(ofSize: pin.id == parent.selectedID ? 12 : 11, weight: .bold)
                    let width = min(118, ceil((name as NSString).size(withAttributes: [.font: font]).width) + 6)
                    let rect = CGRect(x: point.x - width / 2, y: point.y + 2, width: width, height: 18)
                    // 地図の利用規約・Google表記や固定UIを名前で隠さない。
                    guard rect.minY >= map.padding.top, rect.maxY < map.bounds.height - map.padding.bottom - 30 else { continue }
                    let coversPin = pinRects.contains { $0.key != pin.id && $0.value.intersects(rect) }
                    guard !coversPin, !labelRects.contains(where: { $0.intersects(rect) }) else { continue }
                    namedIDs.insert(pin.id)
                    labelRects.append(rect)
                }
            }
            for (index, pin) in parent.pins.enumerated() {
                let marker = markers[pin.id] ?? GMSMarker(position: pin.coordinate)
                let selected = pin.id == parent.selectedID
                marker.position = pin.coordinate
                marker.title = pin.title
                marker.userData = pin.id
                marker.zIndex = selected ? 1000 : Int32(index)
                let showName = namedIDs.contains(pin.id)
                marker.groundAnchor = CGPoint(x: 0.5, y: showName ? (68.0 / 92.0) : 1)
                let signature = "\(pin.genre.rawValue)|\(pin.symbol)|\(pin.mark)|\(pin.showsLikeBadge)|\(selected)|\(pin.scoreTitle ?? "")|\(pin.scoreTag ?? "")|\(showName ? pin.title : "")"
                if signatures[pin.id] != signature {
                    let content: AnyView
                    if let title = pin.scoreTitle {
                        content = AnyView(ScorePin(title: title, tag: pin.scoreTag, isSelected: selected))
                    } else {
                        content = AnyView(PlacePin(symbol: pin.symbol, genre: pin.genre, mark: pin.mark,
                                                  showsLikeBadge: pin.showsLikeBadge, isSelected: selected))
                    }
                    let imageContent: AnyView
                    if showName {
                        imageContent = AnyView(VStack(spacing: 0) {
                            content.frame(height: 60, alignment: .bottom)
                            Text(Self.shortName(pin.title))
                                .font(MeshinowaFont.text(selected ? 12 : 11, weight: .bold))
                                .foregroundStyle(MeshinowaTheme.ink)
                                .lineLimit(1).fixedSize()
                                .shadow(color: .white, radius: 1, x: -1, y: 0)
                                .shadow(color: .white, radius: 1, x: 1, y: 0)
                                .shadow(color: .white, radius: 1, x: 0, y: -1)
                                .shadow(color: .white, radius: 1, x: 0, y: 1)
                                .frame(height: 16)
                        }.frame(width: 120).padding(8))
                    } else {
                        imageContent = AnyView(content.padding(8))
                    }
                    let renderer = ImageRenderer(content: imageContent.environment(\.colorScheme, .light))
                    renderer.scale = UIScreen.main.scale
                    marker.icon = renderer.uiImage
                    signatures[pin.id] = signature
                }
                if marker.map == nil { marker.map = map }
                markers[pin.id] = marker
            }
        }

        private static func shortName(_ name: String) -> String {
            name.count > 10 ? String(name.prefix(10)) + "…" : name
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let id = marker.userData as? String else { return false }
            parent.selectedID = id
            return true
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture { parent.onUserMove?() }
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
            MainActor.assumeIsolated { updatePins(mapView) }
            parent.onCameraEnd?(region, position)
        }
    }
}
