import SwiftUI

/// ボタンから「スワイプと同じ動き」で確定するための依頼。
struct SwipeRequest: Equatable {
    let id = UUID()
    let kind: SwipeDecisionKind
}

/// 最前面のカード＋背面最大2枚。最前面のカードだけに DragGesture(minimumDistance: 0) を付け、
/// タップ（写真の切り替え・地図・詳細）とドラッグ（判断）を1つのジェスチャーで判定する。
struct SwipeCardStackView: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    @ObservedObject var photoLoader: SwipePhotoLoader
    @ObservedObject var placePhotos: SwipePlacePhotoCache
    /// ドラッグ中の横移動量（ガイドの矢印の濃さに使う）。
    @Binding var dragX: CGFloat
    /// ガイドのお手本の動きによる横移動量。
    var demoOffset: CGFloat = 0
    /// ボタンからの確定依頼。
    var request: SwipeRequest?
    /// 指が触れた時（お手本の動きを止める）。
    var onTouch: () -> Void = {}
    var onShowMap: (SwipeCandidate) -> Void = { _ in }
    var onShowDetail: (SwipeCandidate) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @State private var flyOpacity: Double = 1
    @State private var gestureStart: Date?
    @State private var maxDistance: CGFloat = 0
    @State private var regions = SwipeCardRegions.empty
    @State private var photoIndex = 0
    @State private var thresholdKind: SwipeDecisionKind?
    @State private var hapticTrigger = 0
    @State private var isAnimatingOut = false

    var body: some View {
        GeometryReader { proxy in
            let cards = viewModel.deck.visible()
            ZStack {
                ForEach(Array(cards.enumerated().reversed()), id: \.element.id) { position, candidate in
                    let isTop = position == 0
                    SwipeCardView(candidate: candidate,
                                  distanceMeters: viewModel.distance(to: candidate),
                                  isTop: isTop,
                                  photoIndex: isTop ? photoIndex : 0,
                                  dragX: isTop ? offset.width : 0,
                                  photoLoader: photoLoader,
                                  placePhotos: placePhotos,
                                  onRegionsChange: { regions = $0 })
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(isTop ? 1 : 1 - CGFloat(position) * 0.05, anchor: .bottom)
                        .offset(y: isTop ? 0 : CGFloat(position) * 12)
                        .modifier(TopCardMotion(isTop: isTop, offset: offset, demoOffset: demoOffset,
                                                width: proxy.size.width, reduceMotion: reduceMotion,
                                                flyOpacity: flyOpacity))
                        .allowsHitTesting(isTop)
                        .accessibilityHidden(!isTop)
                        .zIndex(isTop ? 1 : -Double(position))
                        .gesture(dragGesture(width: proxy.size.width, candidate: candidate), including: isTop ? .all : .subviews)
                        .modifier(CardAccessibility(isTop: isTop, candidate: candidate,
                                                    distance: viewModel.distance(to: candidate),
                                                    decide: { kind in commit(kind, width: proxy.size.width) },
                                                    showDetail: { onShowDetail(candidate) },
                                                    showMap: { onShowMap(candidate) }))
                }
            }
            .onChange(of: request) { _, request in
                guard let request else { return }
                commit(request.kind, width: proxy.size.width)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .onChange(of: viewModel.deck.top?.id) { _, _ in
            photoIndex = 0
            photoLoader.keepOnly(Set(viewModel.deck.visible().flatMap { $0.photos.map(\.source) }))
            placePhotos.keepImages(for: Set(viewModel.deck.visible().map(\.id)))
        }
    }

    // MARK: - 統合ジェスチャー

    private func dragGesture(width: CGFloat, candidate: SwipeCandidate) -> some Gesture {
        // 位置はカード自身の座標系（傾ける前の向き）で受け取り、カード内の領域と比べる。
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !isAnimatingOut, !viewModel.isProcessing else { return }
                if gestureStart == nil {
                    gestureStart = value.time
                    maxDistance = 0
                    onTouch()
                }
                maxDistance = max(maxDistance, SwipeGestureEvaluator.distance(of: value.translation))
                // 指が動いた瞬間から追従させ、開始を遅らせない。
                offset = value.translation
                dragX = value.translation.width
                let kind = SwipeGestureEvaluator.kindPastThreshold(translationX: value.translation.width, cardWidth: width)
                if kind != thresholdKind {
                    if kind != nil { hapticTrigger += 1 }
                    thresholdKind = kind
                }
            }
            .onEnded { value in
                guard let start = gestureStart else { return }
                gestureStart = nil
                thresholdKind = nil
                let outcome = SwipeGestureEvaluator.evaluateRelease(
                    maxDistance: max(maxDistance, SwipeGestureEvaluator.distance(of: value.translation)),
                    duration: value.time.timeIntervalSince(start),
                    translation: value.translation, predictedEndTranslation: value.predictedEndTranslation,
                    location: value.location, regions: regions)
                switch outcome {
                case .tap(let target):
                    // タップの時はアニメーションなしで元の位置に戻し、指を離した時だけ写真を切り替える。
                    resetWithoutAnimation()
                    handleTap(target, candidate: candidate)
                case .longPress:
                    resetWithoutAnimation()
                case .commit(let kind):
                    commit(kind, width: width)
                case .cancel:
                    dragX = 0
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { offset = .zero }
                }
            }
    }

    private func handleTap(_ target: SwipeTapTarget, candidate: SwipeCandidate) {
        let count = photoLoader.usablePhotos(candidate.photos).count
        switch target {
        case .previousPhoto:
            if count > 0 { photoIndex = max(0, photoIndex - 1) }
        case .nextPhoto:
            if count > 0 { photoIndex = min(count - 1, photoIndex + 1) }
        case .map:
            onShowMap(candidate)
        case .detail:
            onShowDetail(candidate)
        case .none:
            break
        }
    }

    private func resetWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = .zero
            dragX = 0
        }
    }

    /// 画面外へ飛ばしてから確定する。保存に失敗したらカードを戻す。
    private func commit(_ kind: SwipeDecisionKind, width: CGFloat) {
        guard !isAnimatingOut, !viewModel.isProcessing, viewModel.deck.top != nil else { return }
        isAnimatingOut = true
        dragX = kind == .interested ? 1 : -1
        let direction: CGFloat = kind == .interested ? 1 : -1
        withAnimation(.easeIn(duration: SwipeGestureConstants.flyOutDuration)) {
            if reduceMotion {
                flyOpacity = 0
            } else {
                offset = CGSize(width: direction * width * 1.6, height: offset.height + 40)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(SwipeGestureConstants.flyOutDuration))
            let succeeded = await viewModel.decide(kind)
            dragX = 0
            if succeeded {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    offset = .zero
                    flyOpacity = 1
                }
            } else {
                // 保存に失敗したらカードを戻す（エラーは ViewModel がアラートで出す）。
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    offset = .zero
                    flyOpacity = 1
                }
            }
            isAnimatingOut = false
        }
    }
}

/// 最前面のカードの位置・傾き。「視差効果を減らす」がオンの時は傾けず、フェードで切り替える。
private struct TopCardMotion: ViewModifier {
    let isTop: Bool
    let offset: CGSize
    let demoOffset: CGFloat
    let width: CGFloat
    let reduceMotion: Bool
    let flyOpacity: Double

    func body(content: Content) -> some View {
        if isTop {
            let x = offset.width + demoOffset
            content
                .rotationEffect(.degrees(reduceMotion ? 0 : SwipeGestureEvaluator.rotationDegrees(translationX: x, cardWidth: width)),
                                anchor: .bottom)
                .offset(x: reduceMotion ? min(max(x, -24), 24) : x, y: reduceMotion ? 0 : offset.height * 0.3)
                .opacity(flyOpacity)
        } else {
            content
        }
    }
}

/// VoiceOver ではスワイプなしで「行きたい」「イマイチ」「詳細」を操作できるようにする。
private struct CardAccessibility: ViewModifier {
    let isTop: Bool
    let candidate: SwipeCandidate
    let distance: Double
    let decide: (SwipeDecisionKind) -> Void
    let showDetail: () -> Void
    let showMap: () -> Void

    func body(content: Content) -> some View {
        if isTop {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityHint("右にスワイプで行きたい、左にスワイプでイマイチ")
                .accessibilityAction(named: "行きたい") { decide(.interested) }
                .accessibilityAction(named: "イマイチ") { decide(.notInterested) }
                .accessibilityAction(named: "詳細") { showDetail() }
                .accessibilityAction(named: "地図") { showMap() }
        } else {
            content
        }
    }

    private var label: String {
        let rating = candidate.averageRating.formatted(.number.precision(.fractionLength(1)))
        return "\(candidate.name)、友達\(candidate.reviews.count)人の平均 \(rating)、"
            + SwipeDistanceFormatter.accessibilityLabel(meters: distance)
    }
}
