import SwiftUI

struct FriendLensPicker: View {
    @Binding private var lens: FriendLens
    @State private var draft: FriendLens
    @Environment(\.dismiss) private var dismiss

    init(lens: Binding<FriendLens>) {
        _lens = lens
        _draft = State(initialValue: lens.wrappedValue)
    }

    private var count: Int {
        draft.includedFriendIDs(friends: DemoRecommendations.friends,
                                favorites: DemoRecommendations.favoriteFriendIDs).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("誰のおすすめで探す？")
                        .font(MeshinowaFont.text(24, weight: .black, relativeTo: .title2))
                    Text("DEMO · 友達と評価はすべて架空です。")
                        .font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))

                    ForEach(FriendLens.Mode.allCases) { mode in
                        Button { draft.mode = mode } label: {
                            HStack(spacing: 12) {
                                Image(systemName: draft.mode == mode ? "largecircle.fill.circle" : "circle")
                                    .accessibilityHidden(true)
                                Text(mode.title)
                                    .font(MeshinowaFont.text(15, weight: .bold))
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .frame(minHeight: 44)
                            .paperCard(radius: 18, shadowOffset: 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(draft.mode == mode ? .isSelected : [])
                    }

                    if draft.mode == .selectedFriends {
                        Text("友達を選択（複数選択できます）")
                            .font(MeshinowaFont.text(14, weight: .black))
                        ForEach(DemoRecommendations.friends) { friend in
                            friendRow(friend)
                        }
                    } else if draft.mode == .favoriteFriends {
                        Text("デモのお気に入り：たくま・さき・みお")
                            .font(MeshinowaFont.text(14))
                    }

                    Text("現在地は取得・共有しません。選択はこのデモを開いている間だけ有効です。0人でも適用でき、その場合は未評価として表示します。")
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                }
                .padding(20)
            }
            .foregroundStyle(MeshinowaTheme.ink)
            .background(MeshinowaTheme.paper)
            .safeAreaInset(edge: .bottom) {
                Button("\(count)人の評価で表示") {
                    lens = draft
                    dismiss()
                }
                .buttonStyle(PaperButtonStyle())
                .padding(20)
                .background(MeshinowaTheme.paper)
            }
            .navigationTitle("Friend Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private func friendRow(_ friend: DemoFriend) -> some View {
        let isSelected = draft.selectedFriendIDs.contains(friend.id)
        return Button {
            if isSelected {
                draft.selectedFriendIDs.remove(friend.id)
            } else {
                draft.selectedFriendIDs.insert(friend.id)
            }
        } label: {
            HStack(spacing: 12) {
                Text(String(friend.name.prefix(1)))
                    .font(MeshinowaFont.text(15, weight: .black))
                    .frame(width: 36, height: 36)
                    .background(MeshinowaTheme.paper, in: Circle())
                Text(friend.name).font(MeshinowaFont.text(15, weight: .bold))
                Spacer()
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .accessibilityHidden(true)
            }
            .padding(12)
            .paperCard(radius: 16, shadowOffset: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(friend.name)
        .accessibilityValue(isSelected ? "選択中" : "未選択")
    }
}
