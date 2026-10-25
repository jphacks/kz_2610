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
            if let review {
                Label("レビューを編集（★\(review.rating.formatted(.number.precision(.fractionLength(1)))))",
                      systemImage: "square.and.pencil")
            } else {
                Label("行ったらレビューを書く", systemImage: "star")
            }
        }
        .buttonStyle(PaperButtonStyle(kind: review == nil ? .primary : .secondary))
        .disabled(reviews.loadError != nil)
        .sheet(isPresented: $showsEditor) {
            ReviewEditor(item: item, existing: review)
        }
    }
}
