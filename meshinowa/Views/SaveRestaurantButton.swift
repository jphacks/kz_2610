import MapKit
import SwiftUI

struct SaveRestaurantButton: View {
    let item: MKMapItem
    @EnvironmentObject private var saved: SavedRestaurantStore
    @State private var showsError = false

    var body: some View {
        let isSaved = saved.restaurant(for: item)?.isLiked == true
        Button {
            saved.setLiked(item, isLiked: !isSaved)
            showsError = saved.errorMessage != nil
        } label: {
            Label("いいね", systemImage: isSaved ? "heart.fill" : "heart")
        }
        .buttonStyle(PaperButtonStyle(kind: isSaved ? .liked : .secondary))
        .accessibilityValue(isSaved ? "いいね済み" : "未保存")
        .accessibilityHint(isSaved ? "いいねを取り消します" : "この端末にいいねとして保存します")
        .alert("保存を変更できませんでした", isPresented: $showsError) {
            Button("再読み込み") { saved.reload() }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(saved.errorMessage ?? "もう一度お試しください。")
        }
    }
}
