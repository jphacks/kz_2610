import SwiftUI

struct SavedRestaurantsView: View {
    @EnvironmentObject private var saved: SavedRestaurantStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SavedRestaurant?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("行きたい \(saved.restaurants.count)件")
                    .font(MeshinowaFont.text(24, weight: .black, relativeTo: .title2))
                Text("この端末に保存しています。新しく保存した順に表示します。")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)

                if let error = saved.errorMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).font(MeshinowaFont.text(14))
                        Button("再読み込み") { saved.reload() }
                            .buttonStyle(PaperButtonStyle(kind: .secondary))
                    }
                    .padding(16)
                    .paperCard()
                }

                if saved.restaurants.isEmpty && saved.errorMessage == nil {
                    emptyState
                } else {
                    ForEach(saved.restaurants) { restaurant in
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                selected = restaurant
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(restaurant.name)
                                        .font(MeshinowaFont.text(18, weight: .black, relativeTo: .headline))
                                    Text(restaurant.address)
                                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                                        .foregroundStyle(MeshinowaTheme.secondaryText)
                                    Label("お店の情報を見る", systemImage: "chevron.right")
                                        .font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
                                        .foregroundStyle(MeshinowaTheme.green)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            SaveRestaurantButton(item: restaurant.mapItem)
                        }
                        .padding(16)
                        .paperCard()
                    }
                }
            }
            .padding(20)
        }
        .background(MeshinowaTheme.paper)
        .foregroundStyle(MeshinowaTheme.ink)
        .navigationTitle("保存済み")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { restaurant in
            RestaurantInformationView(item: restaurant.mapItem)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "bookmark")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text("行きたいお店はまだありません")
                .font(MeshinowaFont.text(18, weight: .black, relativeTo: .headline))
            Text("地図で気になるお店を見つけて、「行きたい」に保存しましょう。")
                .font(MeshinowaFont.text(14))
            Button("マップでお店を探す") { dismiss() }
                .buttonStyle(PaperButtonStyle())
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .paperCard()
    }
}
