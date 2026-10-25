import Combine
import Foundation

/// サーバーとの同期口。実装は Bridges/CloudflareWantToGoRemote.swift。
protocol SwipeWantToGoRemote {
    /// 追加し、サーバー側の restaurants.id を返す。
    func add(_ entry: SwipeWantToGoEntry) async throws -> String
    func remove(_ entry: SwipeWantToGoEntry) async throws
    func list() async throws -> [SwipeWantToGoRemoteItem]
}

/// 「行きたい」の保存先（いいねとは別）。端末内の JSON を正とし、書き込み成功後にサーバーへ同期する。
/// 通信できない時は端末だけに残し、次の同期で送る。
@MainActor
final class SwipeWantToGoStore: ObservableObject {
    enum StoreError: LocalizedError {
        case unreadable, writeFailed
        var errorDescription: String? {
            switch self {
            case .unreadable: return "行きたいを読み込めないため変更できません。"
            case .writeFailed: return "行きたいに保存できませんでした。空き容量などを確認して、もう一度お試しください。"
            }
        }
    }

    /// アプリ内で1つだけ使う（既存画面からも後で同じものを使えるように）。
    static let shared = SwipeWantToGoStore(fileURL: SwipeDecisionStore.defaultURL(fileName: "want_to_go.json"))

    /// 追加した日時の新しい順。
    @Published private(set) var entries: [SwipeWantToGoEntry] = []
    @Published private(set) var isSyncing = false
    private var pendingRemovals: [SwipeWantToGoEntry] = []
    private let fileURL: URL
    private var canWrite = true
    private var needsResync = false
    /// 変更のたびに裏で同期するか（テストでは手動で sync() を呼ぶ）。
    private let syncsAutomatically: Bool
    var remote: SwipeWantToGoRemote?

    init(fileURL: URL, remote: SwipeWantToGoRemote? = nil, syncsAutomatically: Bool = true) {
        self.fileURL = fileURL
        self.remote = remote
        self.syncsAutomatically = syncsAutomatically
        reload()
    }

    func contains(_ shopID: String) -> Bool {
        entries.contains { $0.id == shopID }
    }

    func reload() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            entries = []; pendingRemovals = []; canWrite = true
            return
        }
        do {
            let file = try JSONDecoder().decode(SwipeWantToGoFile.self, from: Data(contentsOf: fileURL))
            entries = SwipeWantToGoMerge.sorted(file.entries)
            pendingRemovals = file.pendingRemovals
            canWrite = true
        } catch {
            // 壊れたファイルは退避し、空から始める（既存の保存ファイルには触れない）。
            let broken = fileURL.appendingPathExtension("broken")
            try? manager.removeItem(at: broken)
            if (try? manager.moveItem(at: fileURL, to: broken)) != nil {
                entries = []; pendingRemovals = []; canWrite = true
            } else {
                canWrite = false
            }
        }
    }

    /// 右スワイプ確定時。端末への書き込みに失敗したら throw する（サーバーの失敗では throw しない）。
    func add(_ candidate: SwipeCandidate, at date: Date = .now) throws {
        guard !contains(candidate.id) else { return }
        let entry = SwipeWantToGoEntry(candidate: candidate, addedAt: date)
        // 外したばかりの店をまた入れる時は、サーバーへの削除を取りやめる。
        let removals = pendingRemovals.filter { $0.id != candidate.id }
        try persist(entries: [entry] + entries, pendingRemovals: removals)
        scheduleSync()
    }

    func remove(shopID: String) throws {
        guard let entry = entries.first(where: { $0.id == shopID }) else { return }
        var removals = pendingRemovals.filter { $0.id != shopID }
        // 同期の途中（サーバーへの追加が終わる前）に外した時も、サーバー側から消す（削除は何度送っても同じ結果）。
        if entry.isSynced || entry.remoteRestaurantID != nil || isSyncing { removals.append(entry) }
        try persist(entries: entries.filter { $0.id != shopID }, pendingRemovals: removals)
        scheduleSync()
    }

    /// 「行った」（自分のレビュー済み）になった店を外す。
    func removeVisited(isReviewed: (String) -> Bool) {
        for entry in entries where isReviewed(entry.id) {
            try? remove(shopID: entry.id)
        }
    }

    func scheduleSync() {
        guard remote != nil, syncsAutomatically else { return }
        Task { await sync() }
    }

    /// 未送信の削除・追加を送ってから、サーバーの一覧と突き合わせる。失敗しても端末の内容は変えない。
    func sync() async {
        guard let remote, canWrite else { return }
        guard !isSyncing else { needsResync = true; return }
        isSyncing = true
        defer {
            isSyncing = false
            if needsResync { needsResync = false; scheduleSync() }
        }
        do {
            for removal in pendingRemovals {
                try await remote.remove(removal)
                // 待っている間に同じ店がまた追加されていても、削除の記録だけを消す。
                try? persist(entries: entries, pendingRemovals: pendingRemovals.filter { $0.id != removal.id })
            }
            for entry in entries where !entry.isSynced {
                let remoteID = try await remote.add(entry)
                guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { continue }
                var updated = entries
                updated[index].isSynced = true
                updated[index].remoteRestaurantID = remoteID
                try? persist(entries: updated, pendingRemovals: pendingRemovals)
            }
            let items = try await remote.list()
            let merged = SwipeWantToGoMerge.merge(local: entries, pendingRemovalIDs: Set(pendingRemovals.map(\.id)),
                                                  remote: items)
            if merged != entries { try? persist(entries: merged, pendingRemovals: pendingRemovals) }
        } catch {
            // 未接続・通信エラー。次に画面を開いた時にもう一度送る。
        }
    }

    private func persist(entries updated: [SwipeWantToGoEntry], pendingRemovals removals: [SwipeWantToGoEntry]) throws {
        guard canWrite else { throw StoreError.unreadable }
        do {
            let data = try JSONEncoder().encode(SwipeWantToGoFile(entries: updated, pendingRemovals: removals))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            entries = SwipeWantToGoMerge.sorted(updated)
            pendingRemovals = removals
        } catch {
            throw StoreError.writeFailed
        }
    }
}
