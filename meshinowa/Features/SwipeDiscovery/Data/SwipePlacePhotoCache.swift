import Combine
import UIKit

/// 友達の写真がない店で使う、店舗の写真（Google Places）とクレジット。
struct SwipePlacePhoto {
    let image: UIImage
    /// 必須のクレジット（「Google Maps」・提供者・撮影者）。リンク付き。
    let credits: AttributedString
    /// 1行で出す短いクレジット（カード用）。
    let shortCredit: String
}

/// 店舗写真の取得結果を店ごとに覚える。表示中のセッションのメモリだけで、端末には保存しない。
@MainActor
final class SwipePlacePhotoCache: ObservableObject {
    enum State {
        case loading
        case loaded(SwipePlacePhoto)
        /// 写真がない・取得できなかった。星評価ビューを出す。
        case unavailable
    }

    typealias Fetcher = @MainActor (SwipeCandidate) async -> SwipePlacePhoto?

    @Published private(set) var states: [String: State] = [:]
    private let fetcher: Fetcher?

    /// fetcher が nil なら店舗写真を使わない（デモの架空店舗など）。
    init(fetcher: Fetcher?) {
        self.fetcher = fetcher
    }

    var isEnabled: Bool { fetcher != nil }

    func state(for candidate: SwipeCandidate) -> State {
        guard fetcher != nil else { return .unavailable }
        return states[candidate.id] ?? .loading
    }

    func photo(for candidate: SwipeCandidate) -> SwipePlacePhoto? {
        if case .loaded(let photo) = states[candidate.id] { return photo }
        return nil
    }

    func load(_ candidate: SwipeCandidate) {
        guard let fetcher, states[candidate.id] == nil else { return }
        states[candidate.id] = .loading
        Task {
            let photo = await fetcher(candidate)
            states[candidate.id] = photo.map(State.loaded) ?? .unavailable
        }
    }

    /// 表示から外れた店の画像を手放す（取得できなかった記録は残し、同じ店を何度も問い合わせない）。
    func keepImages(for ids: Set<String>) {
        for (id, state) in states {
            if case .loaded = state, !ids.contains(id) { states[id] = nil }
        }
    }
}
