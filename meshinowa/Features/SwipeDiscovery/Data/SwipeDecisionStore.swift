import Foundation

/// swipe_decisions.json の読み書き。既存の保存ディレクトリとは分け、メインスレッドを止めないよう actor で行う。
actor SwipeDecisionStore {
    enum StoreError: LocalizedError {
        case writeFailed
        var errorDescription: String? { "判断を保存できませんでした。空き容量などを確認して、もう一度お試しください。" }
    }

    let fileURL: URL
    private var cache: [SwipeDecision]?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/SwipeDiscovery/<fileName>`。
    static func defaultURL(fileName: String = "swipe_decisions.json") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SwipeDiscovery", isDirectory: true).appendingPathComponent(fileName)
    }

    /// 読み込みに失敗したら空として扱い、壊れたファイルは `.broken` を付けて退避する。
    func load() -> [SwipeDecision] {
        if let cache { return cache }
        let decisions = readFromDisk()
        cache = decisions
        return decisions
    }

    /// 1件を追加または置き換える。書き込みに失敗したら記録は変えない。
    func upsert(_ decision: SwipeDecision) throws {
        var updated = load().filter { $0.id != decision.id }
        updated.append(decision)
        try write(updated)
    }

    func remove(ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        let current = load()
        let updated = current.filter { !ids.contains($0.id) }
        guard updated.count != current.count else { return }
        try write(updated)
    }

    func replaceAll(_ decisions: [SwipeDecision]) throws {
        try write(decisions)
    }

    private func readFromDisk() -> [SwipeDecision] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try JSONDecoder().decode(SwipeDecisionFile.self, from: data)
            var seen = Set<String>()
            // 同じ店の記録が重なっていたら、新しい方を残す。
            return file.decisions.sorted { $0.decidedAt > $1.decidedAt }.filter { seen.insert($0.id).inserted }
        } catch {
            let broken = fileURL.appendingPathExtension("broken")
            try? manager.removeItem(at: broken)
            try? manager.moveItem(at: fileURL, to: broken)
            return []
        }
    }

    /// 一時ファイル経由のアトミック書き込み。成功した時だけ記録を更新する。
    private func write(_ decisions: [SwipeDecision]) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(SwipeDecisionFile(decisions: decisions))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            cache = decisions
        } catch {
            throw StoreError.writeFailed
        }
    }
}
