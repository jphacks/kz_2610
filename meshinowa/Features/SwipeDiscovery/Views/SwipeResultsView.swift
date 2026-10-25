import SwiftUI

/// 結果一覧（F-13・F-16）。「行きたい」「イマイチ」をタブで切り替え、判断した日時の新しい順に出す。
/// 「行きたい」タブは右スワイプしたお店の履歴。地図から追加したものも含めた一覧は保存画面の「行きたい」で見る。
struct SwipeResultsView: View {
    enum Tab: Hashable { case interested, notInterested }

    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.dismiss) private var dismiss
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
                    Text("行きたい \(viewModel.decisions(of: .interested).count)").tag(Tab.interested)
                    Text("イマイチ \(viewModel.decisions(of: .notInterested).count)").tag(Tab.notInterested)
                }
                .pickerStyle(.segmented)
                .padding(16)

                switch tab {
                case .interested: decisionList(.interested)
                case .notInterested: decisionList(.notInterested)
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
            // 開く時に整合チェック。外された「行きたい」と期限切れのイマイチは記録ごと消えて表示しない。
            .task { await viewModel.refreshForResults() }
            .confirmationDialog(dialogTitle, isPresented: Binding(get: { pendingRemoval != nil },
                                                                   set: { if !$0 { pendingRemoval = nil } }),
                                titleVisibility: .visible, presenting: pendingRemoval) { pending in
                Button(pending.action == .delete ? "外す" : "イマイチにする", role: .destructive) {
                    Task {
                        if pending.action == .delete { await viewModel.delete(pending.decision) }
                        else { await viewModel.change(pending.decision, to: .notInterested) }
                    }
                }
            } message: { _ in
                Text("保存画面の「\(viewModel.savedShops.wantToGoTitle)」からも外れます。")
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
        pendingRemoval?.action == .delete ? "「行きたい」から外しますか？" : "イマイチに変えますか？"
    }

    @ViewBuilder private func decisionList(_ kind: SwipeDecisionKind) -> some View {
        let items = viewModel.decisions(of: kind)
        if items.isEmpty {
            ContentUnavailableView(kind == .interested ? "行きたいお店はまだありません" : "イマイチにしたお店はありません",
                                   systemImage: kind == .interested ? "flag" : "hurricane",
                                   description: Text(kind == .interested
                                                     ? "右にスワイプしたお店がここに並び、保存画面の「行きたい」にも入ります。"
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
                Button {
                    if decision.kind == .interested {
                        pendingRemoval = PendingRemoval(decision: decision, action: .change)
                    } else {
                        Task { await viewModel.change(decision, to: .interested) }
                    }
                } label: {
                    Label(decision.kind == .interested ? "イマイチにする" : "行きたいにする",
                          systemImage: decision.kind == .interested ? "hurricane" : "flag")
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
