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

struct ReviewSyncOperation: Codable, Identifiable {
    let id: UUID
    let restaurant: SavedRestaurant
    let review: LocalReview?
    init(restaurant: SavedRestaurant, review: LocalReview?) {
        id = UUID(); self.restaurant = restaurant; self.review = review
    }
}

private struct ReviewDocument: Codable {
    var reviews: [LocalReview]
    var pending: [ReviewSyncOperation]
}

@MainActor
final class LocalReviewStore: ObservableObject {
    @Published private(set) var reviews: [LocalReview] = []
    @Published private(set) var loadError: String?
    @Published private(set) var pending: [ReviewSyncOperation] = []
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
                let data = try Data(contentsOf: fileURL)
                let document: ReviewDocument
                if let current = try? JSONDecoder().decode(ReviewDocument.self, from: data) { document = current }
                else {
                    let old = try JSONDecoder().decode([LocalReview].self, from: data)
                    document = ReviewDocument(reviews: old, pending: old.map { ReviewSyncOperation(restaurant: $0.restaurant, review: $0) })
                }
                let decoded = document.reviews
                guard Set(decoded.map(\.id)).count == decoded.count else { throw CocoaError(.fileReadCorruptFile) }
                for review in decoded {
                    try Self.validate(rating: review.rating, comment: review.comment)
                    guard review.dish.count <= 100, review.photoFileNames.count <= 5,
                          review.photoFileNames.allSatisfy(ReviewPhotoCodec.isSafeFilename) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                }
                reviews = decoded.sorted { $0.updatedAt > $1.updatedAt }
                pending = document.pending
            } else { reviews = []; pending = [] }
            loadError = nil
        } catch {
            loadError = "レビューを読み込めませんでした。元のデータは上書きしていません。"
        }
    }

    func review(for item: MKMapItem) -> LocalReview? {
        reviews.first { $0.restaurant.matches(item) }
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
            try persist([entry] + reviews.filter { $0.id != entry.id }, operation: ReviewSyncOperation(restaurant: entry.restaurant, review: entry))
            onSaved?(entry)
        } catch {
            removePhotos(added)
            throw error
        }
        removePhotos(Array(Set(old?.photoFileNames ?? []).subtracting(retained)))
    }

    func delete(id: String) throws {
        let removed = reviews.first { $0.id == id }
        try persist(reviews.filter { $0.id != id }, operation: removed.map { ReviewSyncOperation(restaurant: $0.restaurant, review: nil) })
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

    func clear() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ReviewDocument(reviews: [], pending: [])).write(to: fileURL, options: .atomic)
        reviews = []; pending = []; loadError = nil
        if FileManager.default.fileExists(atPath: photosDirectory.path) { try FileManager.default.removeItem(at: photosDirectory) }
    }

    func checkpoint() throws -> Data { try JSONEncoder().encode(ReviewDocument(reviews: reviews, pending: pending)) }

    func restoreCheckpoint(_ data: Data) throws {
        try data.write(to: fileURL, options: .atomic)
        reload()
        if loadError != nil { throw ReviewError.unreadableData }
    }

    func enqueueAllForSharing() throws {
        let existing = Set(reviews.map(\.id))
        let deletions = pending.filter { $0.review == nil && !existing.contains($0.restaurant.id) }
        try write(reviews, pending: deletions + reviews.map { ReviewSyncOperation(restaurant: $0.restaurant, review: $0) })
    }

    func acknowledge(_ operation: ReviewSyncOperation) throws {
        try write(reviews, pending: pending.filter { $0.id != operation.id })
    }

    func replace(with restored: [LocalReview], photos: [String: Data], queuesDeletes: Bool = true) throws {
        try replace(with: restored, queuesDeletes: queuesDeletes) { name in
            guard let data = photos[name] else { throw ReviewError.invalidPhoto }
            return data
        }
    }

    func replace(with restored: [LocalReview], queuesDeletes: Bool = true, photoData: (String) throws -> Data) throws {
        guard Set(restored.map(\.id)).count == restored.count else { throw ReviewError.unreadableData }
        for review in restored {
            try Self.validate(rating: review.rating, comment: review.comment)
            guard review.dish.count <= 100, review.photoFileNames.count <= 5,
                  review.photoFileNames.allSatisfy(ReviewPhotoCodec.isSafeFilename),
                  (-90...90).contains(review.restaurant.latitude), (-180...180).contains(review.restaurant.longitude) else { throw ReviewError.unreadableData }
        }
        // Use fresh file names so a failed restore never overwrites existing photos.
        var mapping: [String: String] = [:]
        var staged: [String] = []
        do {
            try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
            for name in Set(restored.flatMap(\.photoFileNames)) {
                let clean = try ReviewPhotoCodec.sanitizedJPEG(from: photoData(name))
                let fresh = UUID().uuidString + ".jpg"
                mapping[name] = fresh; staged.append(fresh)
                try clean.write(to: photosDirectory.appendingPathComponent(fresh), options: .atomic)
            }
            let freshReviews = restored.map {
                LocalReview(restaurant: $0.restaurant, rating: $0.rating, comment: $0.comment,
                            createdAt: $0.createdAt, updatedAt: $0.updatedAt, dish: $0.dish,
                            wantAgain: $0.wantAgain, visitedOn: $0.visitedOn,
                            photoFileNames: $0.photoFileNames.compactMap { mapping[$0] })
            }
            let deleted = queuesDeletes ? reviews.filter { old in !restored.contains { $0.id == old.id } } : []
            let operations = deleted.map { ReviewSyncOperation(restaurant: $0.restaurant, review: nil) }
                + freshReviews.map { ReviewSyncOperation(restaurant: $0.restaurant, review: $0) }
            try write(freshReviews, pending: operations)
        } catch { removePhotos(staged); throw error }
    }

    func removeUnusedPhotos() {
        let used = Set(reviews.flatMap(\.photoFileNames))
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: photosDirectory.path) else { return }
        removePhotos(files.filter { !used.contains($0) })
    }

    private func persist(_ updated: [LocalReview], operation: ReviewSyncOperation? = nil) throws {
        var next = pending
        if let operation {
            next.removeAll { $0.restaurant.id == operation.restaurant.id }
            next.append(operation)
        }
        try write(updated, pending: next)
    }

    private func write(_ updated: [LocalReview], pending next: [ReviewSyncOperation]) throws {
        guard loadError == nil else { throw ReviewError.unreadableData }
        let data = try JSONEncoder().encode(ReviewDocument(reviews: updated, pending: next))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        reviews = updated
        pending = next
    }
}
