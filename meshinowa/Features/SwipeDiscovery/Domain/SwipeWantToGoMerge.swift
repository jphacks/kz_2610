import Foundation

/// 端末の「行きたい」とサーバーの一覧の突き合わせ。純粋関数。
enum SwipeWantToGoMerge {
    /// - Parameters:
    ///   - local: 端末の一覧（未同期の追加を含む）。
    ///   - pendingRemovalIDs: 端末で外したが、サーバーへの削除がまだの店。サーバーにあっても戻さない。
    ///   - remote: サーバーの一覧。
    /// - Returns: 突き合わせ後の端末の一覧（追加した日時の新しい順）。
    static func merge(local: [SwipeWantToGoEntry], pendingRemovalIDs: Set<String>,
                      remote: [SwipeWantToGoRemoteItem]) -> [SwipeWantToGoEntry] {
        let remoteByKey = Dictionary(remote.map { ($0.externalKey, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [SwipeWantToGoEntry] = []
        var seen = Set<String>()
        for var entry in local where seen.insert(entry.id).inserted {
            if let item = remoteByKey[entry.id] {
                entry.isSynced = true
                entry.remoteRestaurantID = item.restaurantID
                result.append(entry)
            } else if !entry.isSynced {
                // まだ送っていない追加は残す（次の同期で送る）。
                result.append(entry)
            }
            // 同期済みなのにサーバーにない店は、サーバー側で外れた（レビューを書いた・他の端末で外した）ので消す。
        }
        for item in remote where !seen.contains(item.externalKey) && !pendingRemovalIDs.contains(item.externalKey) {
            seen.insert(item.externalKey)
            result.append(SwipeWantToGoEntry(
                id: item.externalKey, name: item.name, genre: item.category, address: item.address,
                latitude: item.latitude, longitude: item.longitude, addedAt: item.addedAt,
                remoteRestaurantID: item.restaurantID, isSynced: true))
        }
        return sorted(result)
    }

    static func sorted(_ entries: [SwipeWantToGoEntry]) -> [SwipeWantToGoEntry] {
        entries.sorted { $0.addedAt != $1.addedAt ? $0.addedAt > $1.addedAt : $0.id < $1.id }
    }
}
