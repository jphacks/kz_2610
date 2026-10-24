import Combine
import Foundation
import MapKit

struct LocalReview: Codable, Identifiable {
    var id: String { restaurant.id }
    let restaurant: SavedRestaurant
    let rating: Double
    let comment: String
    let createdAt: Date
    let updatedAt: Date
}

enum ReviewError: LocalizedError {
    case invalidRating, longComment, unreadableData
    var errorDescription: String? {
        switch self {
        case .invalidRating: return "評価は1〜5の範囲で、0.5刻みで選んでください。"
        case .longComment: return "ひとことは300文字以内で入力してください。"
        case .unreadableData: return "既存のレビューを読み込めないため変更できません。再読み込みをお試しください。"
        }
    }
}

@MainActor
final class LocalReviewStore: ObservableObject {
    @Published private(set) var reviews: [LocalReview] = []
    @Published private(set) var loadError: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("meshinowa", isDirectory: true)
            .appendingPathComponent("reviews.json")
        reload()
    }

    func reload() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let decoded = try JSONDecoder().decode([LocalReview].self, from: Data(contentsOf: fileURL))
                guard Set(decoded.map(\.id)).count == decoded.count else { throw CocoaError(.fileReadCorruptFile) }
                for review in decoded { try Self.validate(rating: review.rating, comment: review.comment) }
                reviews = decoded.sorted { $0.updatedAt > $1.updatedAt }
            } else { reviews = [] }
            loadError = nil
        } catch {
            loadError = "レビューを読み込めませんでした。元のデータは上書きしていません。"
        }
    }

    func review(for item: MKMapItem) -> LocalReview? {
        reviews.first { $0.id == SavedRestaurant.identifier(for: item) }
    }

    static func validate(rating: Double, comment: String) throws {
        guard (1...5).contains(rating), rating * 2 == floor(rating * 2) else { throw ReviewError.invalidRating }
        guard comment.count <= 300 else { throw ReviewError.longComment }
    }

    func save(item: MKMapItem, rating: Double, comment: String) throws {
        try Self.validate(rating: rating, comment: comment)
        let old = review(for: item)
        let entry = LocalReview(restaurant: old?.restaurant ?? SavedRestaurant(item: item), rating: rating,
                                comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                                createdAt: old?.createdAt ?? .now, updatedAt: .now)
        try persist([entry] + reviews.filter { $0.id != entry.id })
    }

    func delete(id: String) throws {
        try persist(reviews.filter { $0.id != id })
    }

    private func persist(_ updated: [LocalReview]) throws {
        guard loadError == nil else { throw ReviewError.unreadableData }
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        reviews = updated
    }
}
