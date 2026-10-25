import SwiftUI

/// Friend Lens の切り替え（F-17）。「友達全員」「お気に入りの友達」「選択した友達」で候補に使うレビューを絞る。
struct SwipeLensPicker: View {
    let friends: [SwipeFriendProfile]
    let current: SwipeFriendLens
    let isDemo: Bool
    let onApply: (SwipeFriendLens) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var selected: Set<String>

    enum Mode: CaseIterable { case all, favorites, selected
        var title: String {
            switch self {
            case .all: return "友達全員"
            case .favorites: return "お気に入りの友達"
            case .selected: return "選択した友達"
            }
        }
    }

    init(friends: [SwipeFriendProfile], current: SwipeFriendLens, isDemo: Bool,
         onApply: @escaping (SwipeFriendLens) -> Void) {
        self.friends = friends
        self.current = current
        self.isDemo = isDemo
        self.onApply = onApply
        switch current {
        case .all: _mode = State(initialValue: .all); _selected = State(initialValue: [])
        case .favorites: _mode = State(initialValue: .favorites); _selected = State(initialValue: [])
        case .selected(let ids): _mode = State(initialValue: .selected); _selected = State(initialValue: ids)
        }
    }

    private var lens: SwipeFriendLens {
        switch mode {
        case .all: return .all
        case .favorites: return .favorites
        case .selected: return .selected(selected)
        }
    }

    private var includedCount: Int {
        switch mode {
        case .all: return friends.count
        case .favorites: return friends.filter(\.isFavorite).count
        case .selected: return selected.intersection(friends.map(\.id)).count
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Mode.allCases, id: \.self) { option in
                        Button { mode = option } label: {
                            HStack {
                                Text(option.title)
                                Spacer()
                                if mode == option { Image(systemName: "checkmark").foregroundStyle(SwipeTheme.brand) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(mode == option ? .isSelected : [])
                    }
                } footer: {
                    if isDemo { Text("DEMO · 友達と評価はすべて架空です。") }
                }
                if mode == .favorites {
                    Section("お気に入りの友達") {
                        let favorites = friends.filter(\.isFavorite)
                        if favorites.isEmpty {
                            Text("まだいません。友達タブの☆で選べます。").foregroundStyle(SwipeTheme.secondaryText)
                        }
                        ForEach(favorites) { friend in Text(friend.name) }
                    }
                }
                if mode == .selected {
                    Section("友達を選択（複数選択できます）") {
                        ForEach(friends) { friend in
                            Button {
                                if selected.contains(friend.id) { selected.remove(friend.id) } else { selected.insert(friend.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    SwipeFriendAvatar(name: friend.name, size: 30)
                                    Text(friend.name)
                                    Spacer()
                                    Image(systemName: selected.contains(friend.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(SwipeTheme.brand)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(selected.contains(friend.id) ? "選択中" : "未選択")
                        }
                    }
                }
            }
            .font(SwipeTheme.text(15))
            .safeAreaInset(edge: .bottom) {
                Button {
                    onApply(lens)
                    dismiss()
                } label: {
                    Text("\(includedCount)人のおすすめで探す")
                        .font(SwipeTheme.heading(16))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(SwipeTheme.brand)
                .padding(16)
            }
            .navigationTitle("誰のおすすめで探す？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
        }
    }
}
