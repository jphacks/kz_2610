import MapKit
import SwiftUI

struct RestaurantCollectionControls: View {
    let item: MKMapItem
    @EnvironmentObject private var saved: SavedRestaurantStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsError = false

    var body: some View {
        let entry = saved.restaurant(for: item)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            control("行きたい", symbol: "bookmark", selected: entry?.status == .wantToGo) {
                saved.setVisitStatus(item, status: entry?.status == .wantToGo ? nil : .wantToGo)
            }
            control("行った", symbol: "checkmark.circle", selected: entry?.status == .visited) {
                saved.setVisitStatus(item, status: entry?.status == .visited ? nil : .visited)
            }
            control("お気に入り", symbol: "heart", selected: entry?.isFavorite == true) {
                saved.setFavorite(item, isFavorite: entry?.isFavorite != true)
            }
        }
        .alert("保存を変更できませんでした", isPresented: $showsError) {
            Button("閉じる", role: .cancel) {}
        } message: { Text(saved.errorMessage ?? "もう一度お試しください。") }
    }

    private func control(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Bool) -> some View {
        Button { showsError = !action() } label: {
            VStack(spacing: 6) {
                Image(systemName: selected ? symbol + ".fill" : symbol)
                Text(title).font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(selected ? MeshinowaTheme.card : MeshinowaTheme.ink)
            .background(selected ? MeshinowaTheme.ink : MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MeshinowaTheme.ink, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "登録済み" : "未登録")
        .accessibilityHint(selected ? "登録を解除します" : "登録します")
    }
}
