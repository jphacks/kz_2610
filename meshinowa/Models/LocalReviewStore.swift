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
    let dish: String
    let wantAgain: Bool
    let visitedOn: Date?
    let photoFileNames: [String]

    init(restaurant: SavedRestaurant, rating: Double, comment: String, createdAt: Date, updatedAt: Date,
         dish: String = "", wantAgain: Bool = false, visitedOn: Date? = nil, photoFileNames: [String] = []) {
        self.restaurant = restaurant; self.rating = rating; self.comment = comment
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.dish = dish
        self.wantAgain = wantAgain; self.visitedOn = visitedOn; self.photoFileNames = photoFileNames
    }

    enum CodingKeys: String, CodingKey { case restaurant, rating, comment, createdAt, updatedAt, dish, wantAgain, visitedOn, photoFileNames }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        restaurant = try c.decode(SavedRestaurant.self, forKey: .restaurant)
        rating = try c.decode(Double.self, forKey: .rating)
        comment = try c.decode(String.self, forKey: .comment)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        dish = try c.decodeIfPresent(String.self, forKey: .dish) ?? ""
        wantAgain = try c.decodeIfPresent(Bool.self, forKey: .wantAgain) ?? false
        visitedOn = try c.decodeIfPresent(Date.self, forKey: .visitedOn)
        photoFileNames = try c.decodeIfPresent([String].self, forKey: .photoFileNames) ?? []
    }
}

enum ReviewError: LocalizedError {
    case invalidRating, longComment, unreadableData, invalidPhoto, tooManyPhotos, longDish
    var errorDescription: String? {
        switch self {
        case .invalidRating: return "評価は1〜5の範囲で、0.5刻みで選んでください。"
        case .longComment: return "ひとことは300文字以内で入力してください。"
        case .unreadableData: return "既存のレビューを読み込めないため変更できません。再読み込みをお試しください。"
        case .invalidPhoto: return "この写真は読み込めませんでした。別の写真をお試しください。"
        case .tooManyPhotos: return "写真は5枚までです。"
        case .longDish: return "おすすめ料理は100文字以内で入力してください。"
        }
    }
}

@MainActor
final class LocalReviewStore: ObservableObject {
    @Published private(set) var reviews: [LocalReview] = []
    @Published private(set) var loadError: String?
    /// 端末への書き込みが成功した後に呼ぶ。友達への共有はここから行う。
    var onSaved: ((LocalReview) -> Void)?
    var onDeleted: ((SavedRestaurant) -> Void)?
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
                for review in decoded {
                    try Self.validate(rating: review.rating, comment: review.comment)
                    guard review.dish.count <= 100, review.photoFileNames.count <= 5,
                          review.photoFileNames.allSatisfy(ReviewPhotoCodec.isSafeFilename) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                }
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

    func save(item: MKMapItem, rating: Double, comment: String, dish: String = "", wantAgain: Bool = false,
              visitedOn: Date? = nil, retainedPhotoNames: [String]? = nil, newPhotos: [Data] = []) throws {
        guard loadError == nil else { throw ReviewError.unreadableData }
        try Self.validate(rating: rating, comment: comment)
        let old = review(for: item)
        let retained = retainedPhotoNames ?? old?.photoFileNames ?? []
        guard dish.count <= 100 else { throw ReviewError.longDish }
        guard retained.count + newPhotos.count <= 5 else { throw ReviewError.tooManyPhotos }
        guard Set(retained).count == retained.count,
              Set(retained).isSubset(of: Set(old?.photoFileNames ?? [])) else { throw ReviewError.invalidPhoto }
        let images = try newPhotos.map(ReviewPhotoCodec.sanitizedJPEG)
        var added: [String] = []
        do {
            if !images.isEmpty {
                try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
            }
            for image in images {
                let name = UUID().uuidString + ".jpg"
                added.append(name)
                try image.write(to: photosDirectory.appendingPathComponent(name), options: .atomic)
            }
            let entry = LocalReview(restaurant: old?.restaurant ?? SavedRestaurant(item: item), rating: rating,
                                    comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                                    createdAt: old?.createdAt ?? .now, updatedAt: .now,
                                    dish: dish.trimmingCharacters(in: .whitespacesAndNewlines), wantAgain: wantAgain,
                                    visitedOn: visitedOn, photoFileNames: retained + added)
            try persist([entry] + reviews.filter { $0.id != entry.id })
            onSaved?(entry)
        } catch {
            removePhotos(added)
            throw error
        }
        removePhotos(Array(Set(old?.photoFileNames ?? []).subtracting(retained)))
    }

    func delete(id: String) throws {
        let removed = reviews.first { $0.id == id }
        try persist(reviews.filter { $0.id != id })
        removePhotos(removed?.photoFileNames ?? [])
        if let removed { onDeleted?(removed.restaurant) }
    }

    private var photosDirectory: URL { fileURL.deletingLastPathComponent().appendingPathComponent("review-photos", isDirectory: true) }
    func photoURL(_ filename: String) -> URL? {
        guard ReviewPhotoCodec.isSafeFilename(filename) else { return nil }
        return photosDirectory.appendingPathComponent(filename)
    }
    private func removePhotos(_ names: [String]) {
        for name in names {
            if let url = photoURL(name) { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func persist(_ updated: [LocalReview]) throws {
        guard loadError == nil else { throw ReviewError.unreadableData }
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        reviews = updated
    }
}
