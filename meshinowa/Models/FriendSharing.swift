import Foundation
import MapKit

struct FriendInvite: Decodable {
    let token: String
    let url: URL
}

struct FriendInviteResult: Decodable {
    let state: String
    let profile: FriendStore.Profile?
    let requestId: String?
}

enum InviteLink {
    static func token(from url: URL, backendURL: URL?) -> String? {
        let parts = url.path.split(separator: "/")
        let token: String?
        if url.scheme == "meshinowa", url.host == "invite", parts.count == 1 {
            token = String(parts[0])
        } else if url.scheme == "https" || url.scheme == "http" {
            guard let backendURL, url.scheme == backendURL.scheme,
                  url.host == backendURL.host, url.port == backendURL.port,
                  parts.count == 2, parts[0] == "i" else { return nil }
            token = String(parts[1])
        } else { return nil }
        guard let token, token.count == 64, token.allSatisfy({ "0123456789abcdef".contains($0) }),
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { return nil }
        return token
    }
}

struct CommonWantToGoResult: Decodable {
    let state: String
    let restaurants: [Restaurant]
    struct Restaurant: Decodable, Identifiable {
        let id: String
        let externalKey: String
        let googlePlaceId: String?
        let name: String
        let category: String?
        let address: String
        let latitude: Double
        let longitude: Double

        var mapItem: MKMapItem {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: latitude, longitude: longitude),
                                                       addressDictionary: ["Street": address]))
            item.name = name
            item.pointOfInterestCategory = category.map(MKPointOfInterestCategory.init(rawValue:))
            if let googlePlaceId { item.googleDetails = GoogleRestaurantDetails(placeID: googlePlaceId) }
            return item
        }
    }
}

extension FriendStore {
    func makeInvite(rotate: Bool = false) async throws -> FriendInvite {
        try await call("/invites", method: "POST", json: ["rotate": rotate])
    }

    func inviteResult(token: String, send: Bool = false) async throws -> FriendInviteResult {
        guard token.count == 64, token.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw CloudflareBackend.BackendError.invalidPath
        }
        return try await call("/invites/\(token)" + (send ? "/request" : ""), method: send ? "POST" : "GET")
    }

    func acceptInviteRequest(id: String) async throws {
        guard UUID(uuidString: id) != nil else { throw CloudflareBackend.BackendError.invalidPath }
        let _: [String: Bool] = try await call("/requests/\(id)", method: "PATCH", json: ["accept": true])
        await refresh()
    }

    func commonWantToGo(friendID: String) async throws -> CommonWantToGoResult {
        guard UUID(uuidString: friendID) != nil else { throw CloudflareBackend.BackendError.invalidPath }
        var restaurants: [CommonWantToGoResult.Restaurant] = []
        while true {
            let result: CommonWantToGoResult = try await call("/want-to-go/common", query: [
                URLQueryItem(name: "friend_id", value: friendID),
                URLQueryItem(name: "limit", value: "1000"),
                URLQueryItem(name: "offset", value: String(restaurants.count))])
            guard result.state == "ok" else { return .init(state: result.state, restaurants: []) }
            restaurants += result.restaurants
            if result.restaurants.count < 1000 {
                var unique: [CommonWantToGoResult.Restaurant] = []
                for restaurant in restaurants {
                    let saved = SavedRestaurant(item: restaurant.mapItem, isLiked: false)
                    if !unique.contains(where: { SavedRestaurant(item: $0.mapItem, isLiked: false).isSameStore(as: saved) }) {
                        unique.append(restaurant)
                    }
                }
                return .init(state: "ok", restaurants: unique)
            }
        }
    }
}
