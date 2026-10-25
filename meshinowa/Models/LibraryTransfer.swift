import Combine
import Foundation

/// Explicit, private cloud backup. A compare-and-swap version prevents simultaneous overwrites.
@MainActor
final class LibraryTransfer: ObservableObject {
    struct Snapshot: Codable {
        var schema = 1
        let saved: [SavedRestaurant]
        let reviews: [LocalReview]
    }
    struct Remote: Decodable {
        let version: Int
        let snapshot: Snapshot?
    }
    @Published private(set) var isBusy = false
    @Published var message: String?
    private var saved: SavedRestaurantStore?
    private var reviews: LocalReviewStore?
    private var friends: FriendStore?

    func connect(saved: SavedRestaurantStore, reviews: LocalReviewStore, friends: FriendStore) {
        self.saved = saved; self.reviews = reviews; self.friends = friends
    }

    func backup() async {
        guard !isBusy, let saved, let reviews, let friends else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard reviews.loadError == nil, saved.errorMessage == nil else { throw ReviewError.unreadableData }
            let remote: Remote = try await friends.call("/library")
            let snapshot = Snapshot(saved: saved.restaurants, reviews: reviews.reviews)
            let encoded = try JSONEncoder().encode(snapshot)
            guard encoded.count <= 1_500_000 else { throw CloudflareBackend.BackendError.http(413) }
            for name in Set(reviews.reviews.flatMap(\.photoFileNames)) {
                guard let url = reviews.photoURL(name) else { throw ReviewError.invalidPhoto }
                _ = try await friends.transferData("/library/photos/\(name)", method: "PUT", data: Data(contentsOf: url))
            }
            let value = try JSONSerialization.jsonObject(with: encoded)
            let _: [String: Int] = try await friends.call("/library", method: "PUT", json: ["version":remote.version, "snapshot":value])
            message = "保存・レビュー・写真をバックアップしました。友達には写真と来店日を公開しません。"
        } catch CloudflareBackend.BackendError.http(413) {
            message = "バックアップできる記録の容量を超えています。端末内の記録は保持しています。"
        } catch CloudflareBackend.BackendError.http(409) {
            message = "別の端末でバックアップが更新されました。内容を確認してから、もう一度お試しください。"
        } catch { message = "バックアップできませんでした。端末内の記録は残っています。通信状況を確認してください。" }
    }

    func restore(recoveryKey: String? = nil) async {
        guard !isBusy, let saved, let reviews, let friends else { return }
        isBusy = true
        await friends.pauseReviewSync()
        defer { isBusy = false }
        do {
            // Pause sharing while switching credentials; local records change only after all downloads complete.
            let previousCredential = friends.currentCredential
            if let recoveryKey { try await friends.recover(using: recoveryKey) }
            do {
                let remote: Remote = try await friends.call("/library")
                guard let snapshot = remote.snapshot else {
                    throw TransferError.noBackup
                }
                guard snapshot.schema == 1 else { throw TransferError.invalidVersion }
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent("meshinowa-restore-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: staging) }
                for name in Set(snapshot.reviews.flatMap(\.photoFileNames)) {
                    guard ReviewPhotoCodec.isSafeFilename(name) else { throw ReviewError.invalidPhoto }
                    let data = try await friends.transferData("/library/photos/\(name)")
                    try data.write(to: staging.appendingPathComponent(name), options: .atomic)
                }
                let oldReviews = try reviews.checkpoint()
                let oldSaved = saved.restaurants
                do {
                    try reviews.replace(with: snapshot.reviews, queuesDeletes: recoveryKey == nil) { name in
                        try Data(contentsOf: staging.appendingPathComponent(name))
                    }
                    try saved.replace(with: snapshot.saved)
                } catch {
                    try reviews.restoreCheckpoint(oldReviews)
                    try saved.replace(with: oldSaved)
                    throw error
                }
                reviews.removeUnusedPhotos()
                friends.suspendsReviewSync = false
                await friends.refresh()
                message = "バックアップから記録を復元しました。"
            } catch {
                if recoveryKey != nil { try friends.restoreCredential(previousCredential) }
                throw error
            }
        } catch TransferError.noBackup {
            message = "バックアップがまだありません。元の端末で先にバックアップしてください。"
        } catch {
            message = "復元できませんでした。引き継ぎコードと通信状況を確認してください。元の記録は保持しています。"
        }
        friends.suspendsReviewSync = false
    }

    enum TransferError: Error { case noBackup, invalidVersion }
}
