import Combine
import CoreLocation
import Foundation

/// お店スワイプの状態。判定・デッキ操作・保存は Domain／Data に任せ、ここでは順番と画面の状態だけを扱う。
@MainActor
final class SwipeDeckViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        /// 半径内に友達のレビューがある店がない。
        case empty
        /// 半径内の候補をすべて判断した。
        case finished
        case failed(String)
    }

    /// 半径の目盛り。スライダーはこの段階で止まる。
    static let radiusOptions: [Double] = [500, 1000, 2000, 3000, 5000, 10_000, 20_000, 30_000, 50_000]

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var deck = SwipeDeck()
    /// 判断記録（結果一覧に出す）。整合チェック後のもの。
    @Published private(set) var decisions: [SwipeDecision] = []
    @Published private(set) var friends: [SwipeFriendProfile] = []
    @Published private(set) var guideState: SwipeGuideState
    @Published private(set) var usesDefaultArea = false
    @Published private(set) var isProcessing = false
    /// 「現在地で探す」で位置を取っている間。
    @Published private(set) var isLocating = false
    @Published var radius: Double = 1000
    @Published var category: SwipeCategory?
    @Published var lens: SwipeFriendLens = .all
    /// 保存失敗などのエラー。アラートで出す。
    @Published var errorMessage: String?
    /// 「行きたいに保存しました」などの短い知らせ。
    @Published var notice: String?
    /// 現在の中心地点。
    @Published private(set) var center: CLLocationCoordinate2D

    let dependencies: SwipeDiscoveryDependencies
    private var lastCandidates: [SwipeCandidate] = []
    private var hasLoaded = false
    private let now: () -> Date

    init(dependencies: SwipeDiscoveryDependencies, now: @escaping () -> Date = Date.init) {
        self.dependencies = dependencies
        self.now = now
        guideState = dependencies.guideStore.state
        center = SwipeDiscoveryFeature.defaultCenter
    }

    var savedShops: SavedShopsBridge { dependencies.savedShops }
    var guideMode: SwipeGuideMode { SwipeGuidePolicy.mode(for: guideState) }
    var canUndo: Bool { deck.canUndo && !isProcessing }
    var hasActiveNotInterested: Bool {
        SwipeDecisionReconciler.hasActiveNotInterested(decisions, now: now())
    }

    func distance(to candidate: SwipeCandidate) -> Double {
        SwipeDeckBuilder.distance(fromLatitude: center.latitude, longitude: center.longitude,
                                  toLatitude: candidate.latitude, longitude: candidate.longitude)
    }

    func decisions(of kind: SwipeDecisionKind) -> [SwipeDecision] {
        decisions.filter { $0.kind == kind }.sorted { $0.decidedAt > $1.decidedAt }
    }

    func hoursUntilReturn(_ decision: SwipeDecision) -> Int {
        SwipeDecisionReconciler.hoursUntilReturn(decision, now: now())
    }

    // MARK: - デッキを作る

    /// 画面を開いた時。2回目以降（シートから戻った時など）は何もしない。
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    /// 候補を取り直してデッキを作る（範囲・カテゴリー・Friend Lens を変えた時、再試行）。
    func reload() async {
        phase = .loading
        if let location = await dependencies.location.currentLocation() {
            center = location
            usesDefaultArea = false
        } else {
            center = SwipeDiscoveryFeature.defaultCenter
            usesDefaultArea = true
        }
        friends = await dependencies.provider.friends()
        do {
            lastCandidates = try await dependencies.provider.candidates(near: center, radius: radius, lens: lens)
        } catch {
            phase = .failed("友達のおすすめを読み込めませんでした。通信状況を確認して、もう一度お試しください。")
            return
        }
        await rebuild()
    }

    /// 取得済みの候補でデッキを作り直す（整合チェックを通す）。
    func rebuild() async {
        await savedShops.prepare()
        await reconcile()
        let result = SwipeDeckBuilder.build(
            from: lastCandidates, centerLatitude: center.latitude, centerLongitude: center.longitude,
            radius: radius, category: category, decidedIDs: Set(decisions.map(\.id)),
            isExcluded: savedShops.isExcluded)
        deck.replaceQueue(with: result.candidates)
        if !deck.isEmpty {
            phase = .ready
        } else {
            phase = result.inRadiusCount == 0 ? .empty : .finished
        }
    }

    /// 期限切れのイマイチと、「行きたい」等から外れた右スワイプの記録を消す。
    private func reconcile() async {
        let stored = await dependencies.decisionStore.load()
        let result = SwipeDecisionReconciler.reconcile(stored, now: now(), isExcluded: savedShops.isExcluded)
        if !result.removed.isEmpty {
            try? await dependencies.decisionStore.remove(ids: result.removedIDs)
            deck.forget(ids: result.removedIDs)
        }
        decisions = result.kept
    }

    /// 結果一覧を開く時。消えた記録の店が候補に戻るよう、デッキも作り直す。
    func refreshForResults() async {
        let before = Set(decisions.map(\.id))
        await savedShops.prepare()
        await reconcile()
        if Set(decisions.map(\.id)) != before, phase != .loading, !lastCandidates.isEmpty {
            await rebuild()
        }
    }

    /// 「現在地で探す」。必要なら位置情報の許可を求め、取れたら現在地の周りでデッキを作り直す。
    func useCurrentLocation() async {
        guard !isLocating else { return }
        isLocating = true
        defer { isLocating = false }
        switch await dependencies.location.requestCurrentLocation() {
        case .success:
            await reload()
        case .failure(let error):
            errorMessage = error.message
        }
    }

    func apply(radius: Double, category: SwipeCategory?, lens: SwipeFriendLens) async {
        guard radius != self.radius || category != self.category || lens != self.lens else { return }
        self.radius = radius
        self.category = category
        self.lens = lens
        await reload()
    }

    // MARK: - 判断

    /// 最前面のカードを確定する。右（行きたい）は先に「行きたい」の一覧へ保存し、失敗したら何も記録しない。
    /// - Returns: 確定できたら true。false ならカードを元の位置に戻す。
    @discardableResult
    func decide(_ kind: SwipeDecisionKind) async -> Bool {
        guard let top = deck.top, !isProcessing else { return false }
        isProcessing = true
        defer { isProcessing = false }
        if kind == .interested {
            do {
                try savedShops.addToWantToGo(top)
            } catch {
                errorMessage = "\(savedShops.wantToGoTitle)に保存できませんでした。" + Self.reason(error)
                return false
            }
        }
        let decision = SwipeDecision(candidate: top, kind: kind, decidedAt: now())
        do {
            try await dependencies.decisionStore.upsert(decision)
        } catch {
            if kind == .interested { try? savedShops.removeFromWantToGo(shopID: top.id) }
            errorMessage = Self.reason(error)
            return false
        }
        deck.decide(kind, at: decision.decidedAt)
        decisions.removeAll { $0.id == decision.id }
        decisions.append(decision)
        updateGuide { SwipeGuidePolicy.afterDecision($0) }
        if kind == .interested, !dependencies.guideStore.savedNoticeShown {
            dependencies.guideStore.savedNoticeShown = true
            notice = savedShops.savedNotice
        }
        if deck.isEmpty { phase = .finished }
        return true
    }

    /// 直前の1件を取り消してカードを戻す。右スワイプなら「行きたい」の一覧からも外す。ガイドの状態は戻さない。
    func undo() async {
        guard let last = deck.lastDecision, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        if last.kind == .interested {
            do { try savedShops.removeFromWantToGo(shopID: last.id) } catch {
                errorMessage = Self.reason(error)
                return
            }
        }
        do {
            try await dependencies.decisionStore.remove(ids: [last.id])
        } catch {
            if last.kind == .interested { try? savedShops.addToWantToGo(last.candidate) }
            errorMessage = Self.reason(error)
            return
        }
        deck.undo()
        decisions.removeAll { $0.id == last.id }
        phase = .ready
    }

    /// 一覧から「行きたい」と「イマイチ」を入れ替える（F-16）。
    func change(_ decision: SwipeDecision, to kind: SwipeDecisionKind) async {
        guard decision.kind != kind, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            if kind == .interested { try savedShops.addToWantToGo(decision.candidate) }
            else { try savedShops.removeFromWantToGo(shopID: decision.id) }
        } catch {
            errorMessage = Self.reason(error)
            return
        }
        var updated = decision
        updated.kind = kind
        updated.decidedAt = now()
        do {
            try await dependencies.decisionStore.upsert(updated)
        } catch {
            // 「行きたい」側を元に戻す。
            if kind == .interested { try? savedShops.removeFromWantToGo(shopID: decision.id) }
            else { try? savedShops.addToWantToGo(decision.candidate) }
            errorMessage = Self.reason(error)
            return
        }
        deck.forget(ids: [decision.id])
        decisions.removeAll { $0.id == decision.id }
        decisions.append(updated)
    }

    /// 記録を削除する。削除した店は再び候補に出る。右スワイプなら「行きたい」の一覧からも外す。
    func delete(_ decision: SwipeDecision) async {
        guard !isProcessing else { return }
        isProcessing = true
        if decision.kind == .interested {
            do { try savedShops.removeFromWantToGo(shopID: decision.id) } catch {
                errorMessage = Self.reason(error)
                isProcessing = false
                return
            }
        }
        do {
            try await dependencies.decisionStore.remove(ids: [decision.id])
        } catch {
            if decision.kind == .interested { try? savedShops.addToWantToGo(decision.candidate) }
            errorMessage = Self.reason(error)
            isProcessing = false
            return
        }
        deck.forget(ids: [decision.id])
        decisions.removeAll { $0.id == decision.id }
        isProcessing = false
        await rebuild()
    }

    /// 24時間を待たずにイマイチを全部消す（F-20）。
    func resetNotInterested() async {
        let ids = Set(decisions.filter { $0.kind == .notInterested }.map(\.id))
        guard !ids.isEmpty else { return }
        do {
            try await dependencies.decisionStore.remove(ids: ids)
        } catch {
            errorMessage = Self.reason(error)
            return
        }
        deck.forget(ids: ids)
        decisions.removeAll { ids.contains($0.id) }
        await rebuild()
    }

    // MARK: - ガイド

    /// 「スワイプの使い方を見る」（F-23）。
    func resetGuide() {
        updateGuide { _ in SwipeGuidePolicy.reset() }
    }

    private func updateGuide(_ transform: (SwipeGuideState) -> SwipeGuideState) {
        guideState = transform(guideState)
        dependencies.guideStore.state = guideState
    }

    private static func reason(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "もう一度お試しください。"
    }
}
