import SwiftUI

/// 結果一覧（F-13・F-16）。「気になる」「イマイチ」をタブで切り替え、判断した日時の新しい順に出す。
/// 「行きたい」タブでは、既存画面に入る前の「行きたい」一覧（サーバー同期分も含む）を見られる。
struct SwipeResultsView: View {
    enum Tab: Hashable { case interested, notInterested, wantToGo }

    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var tab: Tab = .interested
    @State private var pendingRemoval: PendingRemoval?

    private struct PendingRemoval: Identifiable {
        enum Action { case change, delete }
        let decision: SwipeDecision
        let action: Action
        var id: String { decision.id + "\(action)" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("表示", selection: $tab) {
                    Text("気になる \(viewModel.decisions(of: .interested).count)").tag(Tab.interested)
                    Text("イマイチ \(viewModel.decisions(of: .notInterested).count)").tag(Tab.notInterested)
                    if viewModel.dependencies.wantToGo != nil {
                        Text("行きたい").tag(Tab.wantToGo)
                    }
                }
                .pickerStyle(.segmented)
                .padding(16)

                switch tab {
                case .interested: decisionList(.interested)
                case .notInterested: decisionList(.notInterested)
                case .wantToGo:
                    if let store = viewModel.dependencies.wantToGo {
                        SwipeWantToGoList(store: store, viewModel: viewModel)
                    }
                }
            }
            .background(SwipeTheme.background)
            .foregroundStyle(SwipeTheme.ink)
            .navigationTitle("結果一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            // 開く時に整合チェック。外された「気になる」と期限切れのイマイチは記録ごと消えて表示しない。
            .task { await viewModel.refreshForResults() }
            .confirmationDialog(dialogTitle, isPresented: Binding(get: { pendingRemoval != nil },
                                                                   set: { if !$0 { pendingRemoval = nil } }),
                                titleVisibility: .visible, presenting: pendingRemoval) { pending in
                Button(pending.action == .delete ? "削除する" : "イマイチにする", role: .destructive) {
                    Task {
                        if pending.action == .delete { await viewModel.delete(pending.decision) }
                        else { await viewModel.change(pending.decision, to: .notInterested) }
                    }
                }
            } message: { _ in
                Text("\(viewModel.savedShops.wantToGoTitle)からも外します。")
            }
            .alert("うまくいきませんでした", isPresented: Binding(get: { viewModel.errorMessage != nil },
                                                           set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("閉じる", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var dialogTitle: String {
        pendingRemoval?.action == .delete ? "「気になる」から削除しますか？" : "イマイチに変えますか？"
    }

    @ViewBuilder private func decisionList(_ kind: SwipeDecisionKind) -> some View {
        let items = viewModel.decisions(of: kind)
        if items.isEmpty {
            ContentUnavailableView(kind == .interested ? "気になるお店はまだありません" : "イマイチにしたお店はありません",
                                   systemImage: kind == .interested ? "heart" : "hurricane",
                                   description: Text(kind == .interested
                                                     ? "右にスワイプしたお店が、ここと「\(viewModel.savedShops.wantToGoTitle)」に入ります。"
                                                     : "イマイチにしたお店は24時間たつと、また候補に出ます。"))
        } else {
            List {
                ForEach(items) { decision in
                    row(decision)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ decision: SwipeDecision) -> some View {
        let candidate = decision.candidate
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.name)
                    .font(SwipeTheme.heading(17))
                    .lineLimit(2)
                Spacer(minLength: 8)
                SwipeStarRating(rating: candidate.averageRating, size: 14)
            }
            SwipeTagRow(candidate: candidate)
            HStack(spacing: 6) {
                Text(decision.decidedAt.formatted(date: .abbreviated, time: .shortened))
                if decision.kind == .notInterested {
                    Text("・あと\(viewModel.hoursUntilReturn(decision))時間で再表示")
                }
            }
            .font(SwipeTheme.text(12, relativeTo: .caption))
            .foregroundStyle(SwipeTheme.secondaryText)
            HStack(spacing: 8) {
                if let url = viewModel.dependencies.directionsURL(for: candidate) {
                    Button { openURL(url) } label: { Label("経路", systemImage: "figure.walk") }
                        .accessibilityHint("Google Mapsで徒歩の経路を開きます")
                }
                Button {
                    if decision.kind == .interested {
                        pendingRemoval = PendingRemoval(decision: decision, action: .change)
                    } else {
                        Task { await viewModel.change(decision, to: .interested) }
                    }
                } label: {
                    Label(decision.kind == .interested ? "イマイチにする" : "気になるにする",
                          systemImage: decision.kind == .interested ? "hurricane" : "heart")
                }
                Button(role: .destructive) {
                    if decision.kind == .interested {
                        pendingRemoval = PendingRemoval(decision: decision, action: .delete)
                    } else {
                        Task { await viewModel.delete(decision) }
                    }
                } label: { Label("削除", systemImage: "trash") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(SwipeTheme.text(12, bold: true, relativeTo: .caption))
            .disabled(viewModel.isProcessing)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
    }
}

/// 「行きたい」の一覧（いいねとは別。既存の保存画面に入るまでの表示場所）。
private struct SwipeWantToGoList: View {
    @ObservedObject var store: SwipeWantToGoStore
    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        if store.entries.isEmpty {
            ContentUnavailableView("行きたいお店はまだありません", systemImage: "flag",
                                   description: Text("右にスワイプしたお店が入ります。レビューを書くと外れます。"))
        } else {
            List {
                Section {
                    ForEach(store.entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.name).font(SwipeTheme.heading(17))
                            Text(entry.address ?? "住所の情報がありません")
                                .font(SwipeTheme.text(12, relativeTo: .caption))
                                .foregroundStyle(SwipeTheme.secondaryText)
                            HStack(spacing: 8) {
                                if let url = directionsURL(entry) {
                                    Button { openURL(url) } label: { Label("経路", systemImage: "figure.walk") }
                                }
                                Button(role: .destructive) {
                                    removeFromWantToGo(entry)
                                } label: { Label("外す", systemImage: "minus.circle") }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Color.clear)
                    }
                } footer: {
                    Text(store.isSyncing ? "同期しています…" : "この端末に保存し、サーバーに接続している時は同期します。")
                        .font(SwipeTheme.text(11, relativeTo: .caption2))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await store.sync() }
        }
    }

    private func directionsURL(_ entry: SwipeWantToGoEntry) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [URLQueryItem(name: "api", value: "1"),
                                  URLQueryItem(name: "destination", value: "\(entry.latitude),\(entry.longitude)"),
                                  URLQueryItem(name: "travelmode", value: "walking")]
        return components?.url
    }

    private func removeFromWantToGo(_ entry: SwipeWantToGoEntry) {
        do {
            try store.remove(shopID: entry.id)
        } catch {
            viewModel.errorMessage = (error as? LocalizedError)?.errorDescription
            return
        }
        // 「気になる」の記録は、次の整合チェックで消えて候補に戻る。
        Task { await viewModel.refreshForResults() }
    }
}
