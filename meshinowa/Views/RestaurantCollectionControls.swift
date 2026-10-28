import MapKit
import SwiftUI

/// 詳しい画面の「行った」の入り口。レビューを書いたお店が行ったお店になる。
struct RestaurantCollectionControls: View {
    let item: MKMapItem
    @EnvironmentObject private var reviews: LocalReviewStore
    @State private var showsEditor = false

    var body: some View {
        let review = reviews.review(for: item)
        Button { showsEditor = true } label: {
            Text(review == nil ? "評価する" : "評価を編集")
        }
        .buttonStyle(PaperButtonStyle())
        .disabled(reviews.loadError != nil)
        .sheet(isPresented: $showsEditor) {
            ReviewEditor(item: item, existing: review)
        }
    }
}
