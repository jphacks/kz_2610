import SwiftUI

struct SearchResultsView: View {
    let results: [RestaurantSearchResult]
    var filterDescription: String? = nil
    var onSelect: (RestaurantSearchResult) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("\(results.count)件のお店")
                        .font(MeshinowaFont.text(22, weight: .black, relativeTo: .title2))
                    if let filterDescription {
                        Text("ジャンル：\(filterDescription)")
                            .font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(MeshinowaTheme.secondaryText)
                    }
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                onSelect(result)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(result.item.name ?? "飲食店")
                                            .font(MeshinowaFont.text(18, weight: .black, relativeTo: .headline))
                                        Text(result.item.restaurantCategory)
                                            .font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
                                        if let address = result.item.placemark.title {
                                            Text(address)
                                                .font(MeshinowaFont.text(12, relativeTo: .caption))
                                                .foregroundStyle(MeshinowaTheme.secondaryText)
                                        }
                                        Label("マップで見る", systemImage: "map")
                                            .font(MeshinowaFont.text(14, weight: .bold))
                                            .foregroundStyle(MeshinowaTheme.green)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            RestaurantPhotoView(item: result.item)
                            SaveRestaurantButton(item: result.item)
                        }
                        .padding(16)
                        .paperCard()
                    }
                }
                .padding(20)
            }
            .background(MeshinowaTheme.paper)
            .foregroundStyle(MeshinowaTheme.ink)
            .navigationTitle("検索結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
