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
    @State private var showsSeal = false
    /// 開いたときに新しい記録だったか。保存後に見出しが「編集」に変わらないよう、最初の値を持ち続ける。
    @State private var startedAsNew: Bool

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
        _startedAsNew = State(initialValue: existing == nil)
    }

    private var canSave: Bool {
        !isSaving && !isLoadingPhotos && rating >= 1 && comment.count <= 300 && dish.count <= 100
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ReviewShopHeader(item: item)

                    BigStarRating(rating: $rating, inline: true)

                    // また行きたい・来店日は、押すだけの札にする。
                    HStack(spacing: 8) {
                        chip("また行きたい", symbol: "arrow.uturn.backward",
                             isOn: wantAgain, tint: MeshinowaTheme.green, soft: MeshinowaTheme.mint,
                             ink: MeshinowaTheme.mintInk) { wantAgain.toggle() }
                        chip(recordsVisitDate ? visitedOn.formatted(.dateTime.month().day()) : "来店日",
                             symbol: "calendar", isOn: recordsVisitDate, tint: MeshinowaTheme.green,
                             soft: MeshinowaTheme.mint, ink: MeshinowaTheme.mintInk) { recordsVisitDate.toggle() }
                    }
                    if recordsVisitDate {
                        DatePicker("来店日", selection: $visitedOn, in: ...Date.now, displayedComponents: .date)
                            .font(MeshinowaFont.text(14))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("ひとこと").font(MeshinowaFont.text(12, weight: .bold))
                                Spacer()
                                Text("\(comment.count) / 300").font(MeshinowaFont.text(12))
                                    .foregroundStyle(comment.count > 300 ? MeshinowaTheme.danger : MeshinowaTheme.secondaryText)
                            }
                            TextField("どこがよかった？　友達に伝えるつもりで", text: $comment, axis: .vertical)
                                .lineLimit(3...8)
                                .frame(minHeight: 60, alignment: .top)
                                .font(MeshinowaFont.text(15))
                                .accessibilityLabel("ひとこと、任意、300文字まで")
                        }
                        .padding(12)
                        inputDivider
                        HStack(spacing: 8) {
                            Text("おすすめ料理").font(MeshinowaFont.text(12, weight: .bold)).frame(width: 72, alignment: .leading)
                            TextField("デミグラスのオムライス", text: $dish)
                                .font(MeshinowaFont.text(14))
                                .accessibilityLabel("おすすめ料理、任意、100文字まで")
                        }
                        .padding(12)
                        if dish.count > 100 {
                            Text("\(dish.count) / 100文字").font(MeshinowaFont.text(12))
                                .foregroundStyle(MeshinowaTheme.danger).padding(.horizontal, 12)
                        }
                        inputDivider
                        photoRow.padding(12)
                    }
                    .background(MeshinowaTheme.field, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MeshinowaTheme.hairline))

                    Label(friends.isAvailable
                          ? "写真・来店日はこの端末だけ。評価とコメントは友達に共有。"
                          : "この端末だけに保存されます", systemImage: "lock")
                        .font(MeshinowaFont.text(12, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MeshinowaTheme.paper)
            .foregroundStyle(MeshinowaTheme.ink)
            .disabled(isSaving)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    if isSaving && !showsSeal { ProgressView().tint(MeshinowaTheme.card) }
                    else { Text(startedAsNew ? "記録する" : "更新する") }
                }
                .buttonStyle(PaperButtonStyle())
                .disabled(!canSave)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(MeshinowaTheme.paper.overlay(alignment: .top) {
                    Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1)
                })
            }
            .navigationTitle(startedAsNew ? "評価する" : "レビューを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.disabled(isSaving)
                }
                if existing != nil && !startedAsNew {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { confirmsDelete = true } label: {
                            Image(systemName: "trash").font(.system(size: 22))
                                .foregroundStyle(MeshinowaTheme.danger)
                        }
                        .buttonStyle(CircleIconButtonStyle())
                        .disabled(isSaving || isLoadingPhotos)
                        .accessibilityLabel("レビューを削除")
                    }
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
        .ratingSealOnSave(rating: rating, isPresented: $showsSeal) { dismiss() }
        .presentationBackground(MeshinowaTheme.paper)
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            await Task.yield()
            do {
                try reviews.save(item: item, rating: rating, comment: comment, dish: dish, wantAgain: wantAgain,
                                 visitedOn: recordsVisitDate ? visitedOn : nil,
                                 retainedPhotoNames: retainedPhotoNames, newPhotos: newPhotos)
                retainedPhotoNames = reviews.review(for: item)?.photoFileNames ?? []
                newPhotos = []
                // 記録できたら判子を押してから閉じる。
                showsSeal = true
            } catch {
                self.error = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func chip(_ title: String, symbol: String, isOn: Bool, tint: Color, soft: Color, ink: Color,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(MeshinowaFont.text(14, weight: isOn ? .bold : .medium))
                .foregroundStyle(isOn ? ink : MeshinowaTheme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Capsule().fill(isOn ? soft : MeshinowaTheme.card))
                .overlay(Capsule().strokeBorder(isOn ? tint : MeshinowaTheme.outline, lineWidth: isOn ? 2 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var inputDivider: some View {
        Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1).padding(.horizontal, 12)
    }

    /// 写真は正方形で横に並べ、最後に「＋写真」の枠を置く。
    private var photoRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(retainedPhotoNames, id: \.self) { name in
                    photoTile(image: reviews.photoURL(name).flatMap { UIImage(contentsOfFile: $0.path) }) {
                        retainedPhotoNames.removeAll { $0 == name }
                    }
                }
                ForEach(newPhotos.indices, id: \.self) { index in
                    photoTile(image: UIImage(data: newPhotos[index])) { newPhotos.remove(at: index) }
                }
                if retainedPhotoNames.count + newPhotos.count < 5 {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 5 - retainedPhotoNames.count - newPhotos.count,
                                 matching: .images, photoLibrary: .shared()) {
                        VStack(spacing: 2) {
                            if isLoadingPhotos { ProgressView() } else {
                                Image(systemName: "camera.badge.plus").font(.system(size: 22, weight: .semibold))
                            }
                            Text("写真").font(MeshinowaFont.text(11, relativeTo: .caption2))
                        }
                        .foregroundStyle(MeshinowaTheme.green)
                        .frame(width: 64, height: 64)
                        .background(MeshinowaTheme.paper, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(MeshinowaTheme.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    .disabled(isLoadingPhotos)
                    .accessibilityLabel("写真を選ぶ、あと\(5 - retainedPhotoNames.count - newPhotos.count)枚")
                    if retainedPhotoNames.isEmpty && newPhotos.isEmpty {
                        Text("5枚まで・位置情報は消して保存")
                            .font(MeshinowaFont.text(12, relativeTo: .caption))
                            .foregroundStyle(MeshinowaTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 160, alignment: .leading)
                    }
                }
            }
        }
    }

    private func photoTile(image: UIImage?, onRemove: @escaping () -> Void) -> some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { MeshinowaTheme.photo }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("写真を外す")
        }
    }
}

struct MyReviewSection: View {
    let item: MKMapItem
    @EnvironmentObject private var reviews: LocalReviewStore
    @State private var showsEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("自分の記録")
                .font(MeshinowaFont.text(17, weight: .black, relativeTo: .headline))
            if let error = reviews.loadError {
                Text(error).font(MeshinowaFont.text(14))
                Button("再読み込み") { reviews.reload() }
            }
            if let review = reviews.review(for: item) {
                Text("★ " + review.rating.formatted(.number.precision(.fractionLength(1))))
                    .font(MeshinowaFont.number(28))
                    .foregroundStyle(MeshinowaTheme.mustardInk)
                if !review.comment.isEmpty { Text(review.comment).font(MeshinowaFont.text(14)) }
                if !review.dish.isEmpty { Text("おすすめ：\(review.dish)").font(MeshinowaFont.text(14)) }
                if review.wantAgain { Label("また行きたい", systemImage: "arrow.uturn.backward").font(MeshinowaFont.text(12, weight: .bold)) }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeshinowaTheme.mustardSoft, in: RoundedRectangle(cornerRadius: 18))
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
