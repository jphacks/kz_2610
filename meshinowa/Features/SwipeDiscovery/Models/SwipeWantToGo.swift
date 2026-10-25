import Foundation

/// 「行きたい」に入れた1店舗。いいね（SavedRestaurant.isLiked）とは別に持ち、Cloudflare と同期する。
struct SwipeWantToGoEntry: Identifiable, Codable, Hashable {
    /// 店舗ID（既存の保存・レビューと同じ体系。サーバーでは restaurants.external_key）。
    let id: String
    var name: String
    var genre: String?
    var address: String?
    var latitude: Double
    var longitude: Double
    var addedAt: Date
    /// サーバー側の restaurants.id。まだ同期していなければ nil。
    var remoteRestaurantID: String?
    /// サーバーに追加済みなら true。
    var isSynced: Bool
    /// 端末だけに置き、サーバーには送らない（デモの架空の店）。以前のファイルにはないので省略可。
    var isLocalOnly: Bool?

    init(candidate: SwipeCandidate, addedAt: Date, isLocalOnly: Bool = false) {
        id = candidate.id
        name = candidate.name
        genre = candidate.genre
        address = candidate.address
        latitude = candidate.latitude
        longitude = candidate.longitude
        self.addedAt = addedAt
        remoteRestaurantID = nil
        isSynced = false
        self.isLocalOnly = isLocalOnly ? true : nil
    }

    init(id: String, name: String, genre: String?, address: String?, latitude: Double, longitude: Double,
         addedAt: Date, remoteRestaurantID: String?, isSynced: Bool, isLocalOnly: Bool? = nil) {
        self.id = id
        self.name = name
        self.genre = genre
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.addedAt = addedAt
        self.remoteRestaurantID = remoteRestaurantID
        self.isSynced = isSynced
        self.isLocalOnly = isLocalOnly
    }

    var sendsToServer: Bool { isLocalOnly != true }
}

/// want_to_go.json の中身。サーバーへの削除が終わっていない店は pendingRemovals に残す。
struct SwipeWantToGoFile: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = SwipeWantToGoFile.currentSchemaVersion
    var entries: [SwipeWantToGoEntry]
    var pendingRemovals: [SwipeWantToGoEntry]
}

/// サーバーにある「行きたい」の1件。
struct SwipeWantToGoRemoteItem: Hashable {
    let restaurantID: String
    let externalKey: String
    let name: String
    let category: String?
    let address: String?
    let latitude: Double
    let longitude: Double
    let addedAt: Date
}
