import MapKit
import SwiftUI

struct ReviewEditor: View {
    let item: MKMapItem
    let existing: LocalReview?
    @EnvironmentObject private var reviews: LocalReviewStore
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Double
    @State private var comment: String
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmsDelete = false

    init(item: MKMapItem, existing: LocalReview?) {
        self.item = item
        self.existing = existing
        _rating = State(initialValue: existing?.rating ?? 0)
        _comment = State(initialValue: existing?.comment ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.name ?? "飲食店")
                        .font(MeshinowaFont.text(20, weight: .black, relativeTo: .title2))
                    StarRatingInput(rating: $rating)
                } header: { Text("星の評価（必須）") }
                Section {
                    TextEditor(text: $comment)
                        .frame(minHeight: 120)
                        .accessibilityLabel("ひとこと、任意、300文字まで")
                    Text("\(comment.count) / 300文字")
                        .foregroundStyle(comment.count > 300 ? .red : MeshinowaTheme.secondaryText)
                } header: { Text("ひとこと（任意）") }
                Section {
                    Text("今はこの端末だけに保存されます。友達への共有はまだ行いません。位置情報も自動では付きません。")
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                }
                if existing != nil {
                    Section {
                        Button("レビューを削除", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .font(MeshinowaFont.text(15))
            .scrollContentBackground(.hidden)
            .background(MeshinowaTheme.paper)
            .disabled(isSaving)
            .safeAreaInset(edge: .bottom) {
                Button {
                    isSaving = true
                    Task { @MainActor in
                        await Task.yield()
                        do {
                            try reviews.save(item: item, rating: rating, comment: comment)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                        isSaving = false
                    }
                } label: {
                    if isSaving { ProgressView().tint(MeshinowaTheme.card) }
                    else { Text(existing == nil ? "投稿する" : "更新する") }
                }
                .buttonStyle(PaperButtonStyle())
                .disabled(isSaving || rating == 0 || comment.count > 300)
                .padding(20)
                .background(MeshinowaTheme.paper)
            }
            .navigationTitle(existing == nil ? "評価する" : "レビューを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .confirmationDialog("このレビューを削除しますか？", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    do {
                        if let existing { try reviews.delete(id: existing.id) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }
            .alert("保存を変更できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
}

struct StarRatingInput: View {
    @Binding var rating: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { value in
                    Button { rating = Double(value) } label: {
                        Image(systemName: rating >= Double(value) ? "star.fill" : (rating >= Double(value) - 0.5 ? "star.leadinghalf.filled" : "star"))
                            .font(.title2)
                            .foregroundStyle(MeshinowaTheme.accent)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value)点にする")
                }
            }
            Text(rating == 0 ? "評価を選んでください" : "あなたの評価：" + rating.formatted(.number.precision(.fractionLength(1))))
                .font(MeshinowaFont.text(17, weight: .black, relativeTo: .headline))
            Stepper("0.5刻みで変更", value: $rating, in: 1...5, step: 0.5)
                .disabled(rating == 0)
                .accessibilityValue(rating.formatted())
        }
    }
}

struct MyReviewSection: View {
    let item: MKMapItem
    @EnvironmentObject private var reviews: LocalReviewStore
    @State private var showsEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("あなたのレビュー")
                .font(MeshinowaFont.text(17, weight: .black, relativeTo: .headline))
            if let error = reviews.loadError {
                Text(error).font(MeshinowaFont.text(14))
                Button("再読み込み") { reviews.reload() }
            }
            if let review = reviews.review(for: item) {
                Text("★ " + review.rating.formatted(.number.precision(.fractionLength(1))))
                    .font(MeshinowaFont.number(22))
                if !review.comment.isEmpty { Text(review.comment).font(MeshinowaFont.text(14)) }
            } else {
                Text("星だけでも記録できます。")
                    .font(MeshinowaFont.text(14))
            }
            Button(reviews.review(for: item) == nil ? "評価する" : "レビューを編集") { showsEditor = true }
                .buttonStyle(PaperButtonStyle(kind: .secondary))
                .disabled(reviews.loadError != nil)
        }
        .padding(18)
        .paperCard()
        .sheet(isPresented: $showsEditor) {
            ReviewEditor(item: item, existing: reviews.review(for: item))
        }
    }
}
