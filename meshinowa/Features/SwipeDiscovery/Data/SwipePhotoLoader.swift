import Combine
import UIKit

/// 友達の写真の読み込み・先読み。表示中のメモリだけに置き、複製や外部への送信はしない。
@MainActor
final class SwipePhotoLoader: ObservableObject {
    @Published private(set) var images: [SwipePhotoSource: UIImage] = [:]
    /// 読み込めなかった写真。カードでは飛ばし、全部失敗したら星評価ビューに切り替える。
    @Published private(set) var failed: Set<SwipePhotoSource> = []
    private var inFlight: [SwipePhotoSource: Task<Void, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func image(for source: SwipePhotoSource) -> UIImage? { images[source] }

    func usablePhotos(_ photos: [SwipeFriendPhoto]) -> [SwipeFriendPhoto] {
        photos.filter { !failed.contains($0.source) }
    }

    func load(_ source: SwipePhotoSource) {
        guard images[source] == nil, !failed.contains(source), inFlight[source] == nil else { return }
        inFlight[source] = Task { [weak self] in
            let image = await Self.fetch(source, session: self?.session ?? .shared)
            guard let self else { return }
            self.inFlight[source] = nil
            if let image { self.images[source] = image } else { self.failed.insert(source) }
        }
    }

    /// 表示中のカードの写真と、次のカードの先頭写真を読む。
    func prefetch(current: [SwipeFriendPhoto], next: [SwipeFriendPhoto]) {
        current.forEach { load($0.source) }
        if let first = next.first { load(first.source) }
    }

    /// 表示から外れた店の写真を手放す（メモリを使いすぎないため）。
    func keepOnly(_ sources: Set<SwipePhotoSource>) {
        images = images.filter { sources.contains($0.key) }
    }

    private static func fetch(_ source: SwipePhotoSource, session: URLSession) async -> UIImage? {
        switch source {
        case .asset(let name):
            return UIImage(named: name)
        case .file(let url):
            let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
            return await prepared(data)
        case .remote(let url):
            guard let result = try? await session.data(from: url) else { return nil }
            if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            return await prepared(result.0)
        }
    }

    private static func prepared(_ data: Data?) async -> UIImage? {
        guard let data, let image = UIImage(data: data) else { return nil }
        return await image.byPreparingForDisplay() ?? image
    }
}
