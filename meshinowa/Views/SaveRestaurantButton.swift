import MapKit
import SwiftUI

struct SaveRestaurantButton: View {
    let item: MKMapItem
    @EnvironmentObject private var saved: SavedRestaurantStore
    @State private var showsError = false

    var body: some View {
        let isSaved = saved.restaurant(for: item)?.status == .wantToGo
        Button {
            saved.setSaved(item, isSaved: !isSaved)
            showsError = saved.errorMessage != nil
        } label: {
            Label(isSaved ? "保存済み" : "行きたい", systemImage: isSaved ? "bookmark.fill" : "bookmark")
        }
        .buttonStyle(PaperButtonStyle(kind: .secondary))
        .accessibilityValue(isSaved ? "行きたいに登録済み" : "未保存")
        .accessibilityHint(isSaved ? "行きたいから解除します" : "この端末の行きたいに保存します")
        .alert("保存を変更できませんでした", isPresented: $showsError) {
            Button("再読み込み") { saved.reload() }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(saved.errorMessage ?? "もう一度お試しください。")
        }
    }
}
