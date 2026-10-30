import SwiftUI

/// お店スワイプの画面。上からナビゲーションバー、カードスタック、ガイドの矢印、アクションバー。
struct SwipeDiscoveryView: View {
    @StateObject private var viewModel: SwipeDeckViewModel
    @StateObject private var photoLoader = SwipePhotoLoader()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragX: CGFloat = 0
    @State private var request: SwipeRequest?
    @State private var showsResults = false
    @State private var showsFilter = false
    @State private var showsRadius = false
    @State private var showsLens = false
    @State private var showsResetConfirmation = false
    /// 絞り込みシートを閉じてから「イマイチをリセット」の確認を出す。
    @State private var resetAfterFilter = false
    @State private var mapCandidate: SwipeCandidate?
    @State private var detailCandidate: SwipeCandidate?
    // ガイド
    @State private var guideVisible = false
    @State private var demoOffset: CGFloat = 0
    @State private var demoDirection = 0
    @State private var demoStopped = false

    init(dependencies: SwipeDiscoveryDependencies) {
        _viewModel = StateObject(wrappedValue: SwipeDeckViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.usesDefaultArea && viewModel.phase != .loading {
                    defaultAreaBanner
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SwipeTheme.background.ignoresSafeArea())
            .foregroundStyle(SwipeTheme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .overlay(alignment: .top) { noticeToast }
        }
        .environmentObject(photoLoader)
        .task { await viewModel.loadIfNeeded() }
        .sheet(isPresented: $showsResults) { SwipeResultsView(viewModel: viewModel) }
        .sheet(isPresented: $showsFilter, onDismiss: {
            if resetAfterFilter {
                resetAfterFilter = false
                showsResetConfirmation = true
            }
        }) {
            SwipeFilterSheet(viewModel: viewModel,
                             onShowGuide: { viewModel.resetGuide() },
                             onResetNotInterested: { resetAfterFilter = true })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsRadius) {
            SwipeRadiusSheet(viewModel: viewModel)
                .presentationDetents([.height(190)])
        }
        .sheet(isPresented: $showsLens) {
            SwipeLensPicker(friends: viewModel.friends, current: viewModel.lens,
                            isDemo: viewModel.dependencies.isDemo) { lens in
                Task { await viewModel.apply(radius: viewModel.radius, category: viewModel.category, lens: lens) }
            }
        }
        .sheet(item: $mapCandidate) { candidate in
            SwipeLargeMapSheet(candidate: candidate, distanceMeters: viewModel.distance(to: candidate))
        }
        .sheet(item: $detailCandidate) { candidate in
            SwipeCandidateDetailSheet(candidate: candidate, distanceMeters: viewModel.distance(to: candidate),
                                      placePhotos: viewModel.dependencies.placePhotos)
                .environmentObject(photoLoader)
        }
        .confirmationDialog("イマイチをリセットしますか？", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("リセットする", role: .destructive) { Task { await viewModel.resetNotInterested() } }
        } message: {
            Text("24時間以内にイマイチにしたお店が、また候補に出ます。")
        }
        .alert("うまくいきませんでした", isPresented: Binding(
            get: { viewModel.errorMessage != nil && !showsResults },
            set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - ナビゲーションバー

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("閉じる")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text("お店スワイプ")
                    .font(SwipeTheme.heading(17))
                Button { showsLens = true } label: {
                    HStack(spacing: 3) {
                        Text(viewModel.lens.shortTitle)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(SwipeTheme.text(11, bold: true, relativeTo: .caption2))
                    .foregroundStyle(SwipeTheme.tagText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(SwipeTheme.tagBackground, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Friend Lens、\(viewModel.lens.title)")
                .accessibilityHint("誰のおすすめで探すかを変えます")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showsResults = true } label: { Image(systemName: "list.bullet.rectangle") }
                .accessibilityLabel("結果一覧")
            Button { showsFilter = true } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("絞り込み")
        }
    }

    // MARK: - 状態ごとの中身（F-14）

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .loading:
            stateView(symbol: nil, title: "友達のおすすめを集めています…", message: nil) { EmptyView() }
        case .failed(let message):
            stateView(symbol: "wifi.exclamationmark", title: "読み込めませんでした", message: message) {
                primaryButton("再試行") { Task { await viewModel.reload() } }
            }
        case .empty:
            stateView(symbol: "person.2.slash",
                      title: "近くに友達のレビューがありません",
                      message: "\(SwipeDistanceFormatter.radiusText(meters: viewModel.radius))以内に、友達がレビューしたお店が見つかりませんでした。") {
                primaryButton("範囲を変える") { showsRadius = true }
                secondaryButton("友達を見る") { dismiss() }
            }
        case .finished:
            stateView(symbol: "checkmark.seal", title: "この近くの友達のおすすめは全部見ました",
                      message: "右にスワイプしたお店は「\(viewModel.savedShops.wantToGoTitle)」に入っています。") {
                primaryButton("範囲を変える") { showsRadius = true }
                if viewModel.hasActiveNotInterested {
                    secondaryButton("イマイチをリセット") { showsResetConfirmation = true }
                }
                secondaryButton("結果一覧を見る") { showsResults = true }
                if viewModel.canUndo {
                    secondaryButton("直前の判断を戻す") { Task { await viewModel.undo() } }
                }
            }
        case .ready:
            deckContent
        }
    }

    private var deckContent: some View {
        VStack(spacing: 0) {
            SwipeCardStackView(viewModel: viewModel, photoLoader: photoLoader,
                               placePhotos: viewModel.dependencies.placePhotos,
                               dragX: $dragX, demoOffset: demoOffset, request: request,
                               onTouch: stopDemo,
                               onShowMap: { mapCandidate = $0 },
                               onShowDetail: { detailCandidate = $0 })
                .padding(.horizontal, 16)
                .padding(.top, 8)
            SwipeGuideOverlay(mode: viewModel.guideMode, dragX: dragX, demoDirection: demoDirection,
                              isVisible: guideVisible && viewModel.guideMode != .none)
                .padding(.vertical, 8)
            SwipeActionBar(canUndo: viewModel.canUndo,
                           isEnabled: viewModel.deck.top != nil && !viewModel.isProcessing,
                           onUndo: { Task { await viewModel.undo() } },
                           onDecide: { kind in
                               stopDemo()
                               request = SwipeRequest(kind: kind)
                           })
                .padding(.bottom, 12)
        }
        // ガイド：最初のカードが出てから約0.4秒後に出し、初回はお手本の動きを2回見せる。
        .task(id: "\(viewModel.deck.top?.id ?? "")|\(viewModel.guideMode)") {
            await runGuide()
        }
    }

    // MARK: - ガイド

    private func runGuide() async {
        let mode = viewModel.guideMode
        guard mode != .none, viewModel.deck.top != nil else {
            guideVisible = false
            return
        }
        if !guideVisible {
            try? await Task.sleep(for: .seconds(SwipeGuidePolicy.appearDelay))
            guard !Task.isCancelled else { return }
            guideVisible = true
        }
        guard mode == .initial, !reduceMotion else { return }
        demoStopped = false
        let step = SwipeGuidePolicy.demoCycleDuration / 4
        // 右へ約40pt → 中央 → 左へ約40pt → 中央。
        let moves: [(offset: CGFloat, direction: Int)] = [
            (SwipeGuidePolicy.demoTravel, 1), (0, 0), (-SwipeGuidePolicy.demoTravel, -1), (0, 0)
        ]
        for _ in 0..<SwipeGuidePolicy.demoRepeatCount {
            for (offset, direction) in moves {
                guard !Task.isCancelled, !demoStopped else {
                    if Task.isCancelled {
                        demoOffset = 0
                        demoDirection = 0
                    }
                    return
                }
                withAnimation(.easeInOut(duration: step)) {
                    demoOffset = offset
                    demoDirection = direction
                }
                try? await Task.sleep(for: .seconds(step))
            }
        }
    }

    /// 指が触れたらお手本の動きをすぐ止める。
    private func stopDemo() {
        guard !demoStopped || demoOffset != 0 else { return }
        demoStopped = true
        withAnimation(.easeOut(duration: 0.15)) {
            demoOffset = 0
            demoDirection = 0
        }
    }

    // MARK: - 部品

    /// 既定エリアで探している時の表示。押した時だけ位置情報の許可を求める（地図と同じ方針）。
    private var defaultAreaBanner: some View {
        HStack(spacing: 8) {
            Label("\(SwipeDiscoveryFeature.defaultAreaName)で探しています", systemImage: "location.slash")
                .font(SwipeTheme.text(12, relativeTo: .caption))
                .foregroundStyle(SwipeTheme.bodyText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityLabel("位置情報を使っていないため、\(SwipeDiscoveryFeature.defaultAreaName)で探しています")
            Button {
                Task { await viewModel.useCurrentLocation() }
            } label: {
                HStack(spacing: 4) {
                    if viewModel.isLocating {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "location.fill").font(.system(size: 11, weight: .bold))
                    }
                    Text("現在地で探す").font(SwipeTheme.text(12, bold: true, relativeTo: .caption))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(SwipeTheme.brand, in: Capsule())
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLocating)
            .accessibilityHint("位置情報の許可を求め、現在地の周りの友達のおすすめを探します")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .background(SwipeTheme.field, in: Capsule())
        .overlay(Capsule().strokeBorder(SwipeTheme.hairline))
        .padding(.top, 4)
    }

    @ViewBuilder private var noticeToast: some View {
        if let notice = viewModel.notice {
            Text(notice)
                .font(SwipeTheme.text(14, bold: true))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(SwipeTheme.ink.opacity(0.88), in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { viewModel.notice = nil }
                }
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func stateView<Actions: View>(symbol: String?, title: String, message: String?,
                                          @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 14) {
            Spacer()
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(SwipeTheme.brand)
                    .frame(width: 76, height: 76)
                    .background(SwipeTheme.tagBackground, in: Circle())
                    .accessibilityHidden(true)
            } else {
                ProgressView().controlSize(.large).tint(SwipeTheme.brand)
            }
            Text(title)
                .font(SwipeTheme.heading(19))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(SwipeTheme.text(14))
                    .foregroundStyle(SwipeTheme.bodyText)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) { actions() }
                .padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(SwipeTheme.heading(16)).frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(SwipeTheme.brand)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(SwipeTheme.heading(16)).frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered)
        .tint(SwipeTheme.ink)
    }
}

/// 「範囲を変える」で出す、半径だけのシート。
struct SwipeRadiusSheet: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var radius: Double = 1000

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SwipeRadiusSlider(radius: $radius)
                } header: {
                    SwipeRadiusHeader(radius: radius)
                }
            }
            .font(SwipeTheme.text(15))
            .navigationTitle("範囲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("この範囲で探す") {
                        let selectedRadius = radius
                        dismiss()
                        Task { await viewModel.apply(radius: selectedRadius, category: viewModel.category, lens: viewModel.lens) }
                    }
                }
            }
            .onAppear { radius = viewModel.radius }
        }
    }
}

/// 半径の見出し。選んでいる値を右に出す。
struct SwipeRadiusHeader: View {
    let radius: Double

    var body: some View {
        HStack {
            Text("半径")
            Spacer()
            Text(SwipeDistanceFormatter.radiusText(meters: radius))
                .font(SwipeTheme.text(15, bold: true))
                .foregroundStyle(SwipeTheme.brand)
                .monospacedDigit()
        }
    }
}

/// 半径のスライダー。目盛り（radiusOptions）の番号で動かし、半径（m）に読み替える。
struct SwipeRadiusSlider: View {
    @Binding var radius: Double

    private var options: [Double] { SwipeDeckViewModel.radiusOptions }

    private var step: Binding<Double> {
        Binding(
            get: { Double(options.lastIndex { $0 <= radius } ?? 0) },
            set: { radius = options[min(max(Int($0.rounded()), 0), options.count - 1)] })
    }

    var body: some View {
        Slider(value: step, in: 0...Double(options.count - 1), step: 1) {
            Text("半径")
        } minimumValueLabel: {
            Text(SwipeDistanceFormatter.radiusText(meters: options[0]))
        } maximumValueLabel: {
            Text(SwipeDistanceFormatter.radiusText(meters: options[options.count - 1]))
        }
        .tint(SwipeTheme.brand)
        .accessibilityValue(SwipeDistanceFormatter.radiusText(meters: radius))
        .font(SwipeTheme.text(12, relativeTo: .caption))
        .foregroundStyle(.secondary)
    }
}

/// 絞り込み（F-18）。半径・カテゴリー・ガイドの再表示（F-23）・イマイチのリセット（F-20）。
struct SwipeFilterSheet: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    let onShowGuide: () -> Void
    let onResetNotInterested: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var radius: Double = 1000
    @State private var category: SwipeCategory?
    @State private var guideReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SwipeRadiusSlider(radius: $radius)
                } header: {
                    SwipeRadiusHeader(radius: radius)
                }
                Section("カテゴリー") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("すべて", isOn: category == nil) { category = nil }
                            ForEach(SwipeCategory.allCases) { option in
                                chip(option.tagName, isOn: category == option) { category = option }
                                    .accessibilityLabel(option.name)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    Button(guideReset ? "次のカードで使い方を出します" : "スワイプの使い方を見る") {
                        onShowGuide()
                        guideReset = true
                    }
                    .disabled(guideReset)
                    Button("イマイチをリセット", role: .destructive) {
                        onResetNotInterested()
                        dismiss()
                    }
                    .disabled(!viewModel.hasActiveNotInterested)
                } footer: {
                    Text("イマイチにしたお店は24時間たつと、また候補に出ます。")
                }
            }
            .font(SwipeTheme.text(15))
            .navigationTitle("絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("この条件で探す") {
                        let selectedRadius = radius, selectedCategory = category
                        dismiss()
                        Task { await viewModel.apply(radius: selectedRadius, category: selectedCategory, lens: viewModel.lens) }
                    }
                }
            }
            .onAppear {
                radius = viewModel.radius
                category = viewModel.category
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SwipeTheme.text(13, bold: isOn, relativeTo: .caption))
                .foregroundStyle(isOn ? Color.white : SwipeTheme.tagText)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(isOn ? SwipeTheme.brand : SwipeTheme.tagBackground, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
