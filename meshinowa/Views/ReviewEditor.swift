import MapKit
import SwiftUI
import PhotosUI

struct ReviewEditor: View {
    let item: MKMapItem
    let existing: LocalReview?
    @EnvironmentObject private var reviews: LocalReviewStore
    @EnvironmentObject private var friends: FriendStore
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Double
    @State private var comment: String
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var dish: String
    @State private var wantAgain: Bool
    @State private var recordsVisitDate: Bool
    @State private var visitedOn: Date
    @State private var retainedPhotoNames: [String]
    @State private var newPhotos: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false

    init(item: MKMapItem, existing: LocalReview?, initialRating: Double? = nil) {
        self.item = item
        self.existing = existing
        _rating = State(initialValue: initialRating.flatMap { $0 > 0 ? $0 : nil } ?? existing?.rating ?? 0)
        _comment = State(initialValue: existing?.comment ?? "")
        _dish = State(initialValue: existing?.dish ?? "")
        _wantAgain = State(initialValue: existing?.wantAgain ?? false)
        _recordsVisitDate = State(initialValue: existing?.visitedOn != nil)
        _visitedOn = State(initialValue: existing?.visitedOn ?? .now)
        _retainedPhotoNames = State(initialValue: existing?.photoFileNames ?? [])
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
                Section("追加の記録（すべて任意）") {
                    TextField("おすすめ料理（100文字まで）", text: $dish)
                    Toggle("また行きたい", isOn: $wantAgain)
                    Toggle("来店日を記録する", isOn: $recordsVisitDate)
                    if recordsVisitDate {
                        DatePicker("来店日", selection: $visitedOn, in: ...Date.now, displayedComponents: .date)
                    }
                }
                Section("写真（任意、5枚まで）") {
                    photoAttachments
                    if retainedPhotoNames.count + newPhotos.count < 5 {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 5 - retainedPhotoNames.count - newPhotos.count,
                                     matching: .images, photoLibrary: .shared()) {
                            Label("写真を選ぶ", systemImage: "photo.on.rectangle.angled")
                        }
                        .disabled(isLoadingPhotos)
                    }
                    if isLoadingPhotos { ProgressView("写真を読み込み中") }
                    Text("写真の位置情報などのメタデータは保存しません。")
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                }
                Section {
                    Text(friends.isAvailable
                         ? "評価・ひとこと・おすすめ料理は友達に共有されます。写真と来店日はこの端末だけに保存します。位置情報は自動では付きません。"
                         : "サーバーに接続していないため、この端末だけに保存されます。位置情報は自動では付きません。")
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
                            try reviews.save(item: item, rating: rating, comment: comment, dish: dish, wantAgain: wantAgain,
                                             visitedOn: recordsVisitDate ? visitedOn : nil,
                                             retainedPhotoNames: retainedPhotoNames, newPhotos: newPhotos)
                            retainedPhotoNames = reviews.review(for: item)?.photoFileNames ?? []
                            newPhotos = []
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                        isSaving = false
                    }
                } label: {
                    if isSaving { ProgressView().tint(MeshinowaTheme.card) }
                    else { Text(existing == nil ? "投稿する" : "更新する") }
                }
                .buttonStyle(PaperButtonStyle())
                .disabled(isSaving || isLoadingPhotos || rating == 0 || comment.count > 300 || dish.count > 100)
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
            .interactiveDismissDisabled(isSaving || isLoadingPhotos)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                isLoadingPhotos = true
                Task { @MainActor in
                    defer { isLoadingPhotos = false; pickerItems = [] }
                    do {
                        var loaded: [Data] = []
                        for item in items {
                            guard let data = try await item.loadTransferable(type: Data.self) else { throw ReviewError.invalidPhoto }
                            let sanitized = try await Task.detached(priority: .userInitiated) {
                                try ReviewPhotoCodec.sanitizedJPEG(from: data)
                            }.value
                            loaded.append(sanitized)
                        }
                        guard retainedPhotoNames.count + newPhotos.count + loaded.count <= 5 else { throw ReviewError.tooManyPhotos }
                        newPhotos.append(contentsOf: loaded)
                    } catch { self.error = error.localizedDescription }
                }
            }
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

    @ViewBuilder private var photoAttachments: some View {
        ForEach(retainedPhotoNames, id: \.self) { name in
            HStack {
                ReviewPhotoThumbnail(url: reviews.photoURL(name))
                Spacer()
                Button("写真を外す", role: .destructive) { retainedPhotoNames.removeAll { $0 == name } }
            }
        }
        ForEach(newPhotos.indices, id: \.self) { index in
            HStack {
                if let image = UIImage(data: newPhotos[index]) {
                    Image(uiImage: image).resizable().scaledToFit().frame(height: 80)
                }
                Spacer()
                Button("写真を外す", role: .destructive) { newPhotos.remove(at: index) }
            }
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
                if !review.dish.isEmpty { Text("おすすめ：\(review.dish)").font(MeshinowaFont.text(14)) }
                if review.wantAgain { Label("また行きたい", systemImage: "heart.fill").font(MeshinowaFont.text(12, weight: .bold)) }
                if let date = review.visitedOn { Text(date, style: .date).font(MeshinowaFont.text(12, relativeTo: .caption)) }
                if !review.photoFileNames.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(review.photoFileNames, id: \.self) { ReviewPhotoThumbnail(url: reviews.photoURL($0)) }
                        }
                    }
                }
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

struct ReviewPhotoThumbnail: View {
    let url: URL?
    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Label("写真を読み込めません", systemImage: "photo")
            }
        }
        .frame(width: 100, height: 100)
        .accessibilityLabel("レビューに添付した写真")
    }
}
