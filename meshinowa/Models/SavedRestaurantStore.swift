import Combine
import Foundation
import MapKit

@MainActor
final class SavedRestaurantStore: ObservableObject {
    @Published private(set) var restaurants: [SavedRestaurant] = []
    @Published var errorMessage: String?
    private let fileURL: URL
    private var canWrite = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("meshinowa", isDirectory: true)
            .appendingPathComponent("saved-restaurants.json")
        reload()
    }

    func reload() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode([SavedRestaurant].self, from: data)
                guard decoded.allSatisfy({
                    (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
                }), Set(decoded.map(\.id)).count == decoded.count else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                restaurants = decoded.sorted { $0.savedAt > $1.savedAt }
            } else {
                restaurants = []
            }
            canWrite = true
            errorMessage = nil
        } catch {
            // 読み込めない既存データを空の一覧で上書きしない。
            canWrite = false
            errorMessage = "保存したお店を読み込めませんでした。元のデータは上書きしていません。再読み込みをお試しください。"
        }
    }

    func contains(_ item: MKMapItem) -> Bool {
        let id = SavedRestaurant.identifier(for: item)
        return restaurants.contains { $0.id == id }
    }

    func restaurant(for item: MKMapItem) -> SavedRestaurant? {
        restaurants.first { $0.id == SavedRestaurant.identifier(for: item) }
    }

    @discardableResult func setLiked(_ item: MKMapItem, isLiked: Bool) -> Bool {
        var entry = restaurant(for: item) ?? SavedRestaurant(item: item, isLiked: false)
        entry.isLiked = isLiked
        return update(entry)
    }

    private func update(_ entry: SavedRestaurant) -> Bool {
        let others = restaurants.filter { $0.id != entry.id }
        let updated = (entry.isLiked ? [entry] + others : others)
            .sorted { $0.savedAt > $1.savedAt }
        return persist(updated)
    }

    private func persist(_ updated: [SavedRestaurant]) -> Bool {
        guard canWrite else {
            errorMessage = "保存データを読み込めていないため、変更できません。再読み込みをお試しください。"
            return false
        }
        do {
            let data = try JSONEncoder().encode(updated)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            // 書き込み成功後に表示を更新する。失敗時は保存済みに見せない。
            restaurants = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "お店の保存を変更できませんでした。空き容量などを確認して、もう一度お試しください。"
            return false
        }
    }
}
