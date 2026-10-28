import SwiftUI

/// 情報エリアをタップした時の詳細（F-12）。店名・ジャンル・住所と、友達レビューの一覧。
struct SwipeCandidateDetailSheet: View {
    let candidate: SwipeCandidate
    let distanceMeters: Double
    @ObservedObject var placePhotos: SwipePlacePhotoCache
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(candidate.name)
                            .font(SwipeTheme.heading(26, relativeTo: .title))
                            .accessibilityAddTraits(.isHeader)
                        SwipeTagRow(candidate: candidate)
                        HStack(spacing: 8) {
                            SwipeStarRating(rating: candidate.averageRating, size: 18)
                            Text("友達\(candidate.reviews.count)人の平均")
                                .font(SwipeTheme.text(14))
                                .foregroundStyle(SwipeTheme.bodyText)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        infoRow("fork.knife", candidate.genreLabel)
                        infoRow("mappin.and.ellipse", candidate.address ?? "住所の情報がありません")
                        infoRow("figure.walk", SwipeDistanceFormatter.label(meters: distanceMeters) + "（直線距離の目安）")
                    }
                    if let photo = placePhotos.photo(for: candidate), candidate.photos.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityLabel("お店の写真")
                            Text(photo.credits)
                                .font(.system(size: 11))
                                .foregroundStyle(SwipeTheme.secondaryText)
                                .tint(SwipeTheme.brand)
                        }
                    }
                    Text("友達のレビュー")
                        .font(SwipeTheme.heading(18))
                        .padding(.top, 4)
                    ForEach(candidate.reviews) { review in
                        SwipeReviewRow(review: review)
                    }
                }
                .padding(20)
            }
            .foregroundStyle(SwipeTheme.ink)
            .background(SwipeTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func infoRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(SwipeTheme.text(15))
                .foregroundStyle(SwipeTheme.bodyText)
                .textSelection(.enabled)
        }
    }
}

private struct SwipeReviewRow: View {
    let review: SwipeFriendReview
    @EnvironmentObject private var photoLoader: SwipePhotoLoader

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SwipeFriendAvatar(name: review.friendName, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(review.friendName).font(SwipeTheme.text(14, bold: true))
                    Spacer()
                    SwipeStarRating(rating: review.rating, size: 15)
                }
                if let comment = review.comment {
                    Text(comment)
                        .font(SwipeTheme.text(15))
                        .foregroundStyle(SwipeTheme.bodyText)
                }
                if let dish = review.recommendedDish {
                    Label("おすすめ：\(dish)", systemImage: "fork.knife")
                        .font(SwipeTheme.text(13, relativeTo: .caption))
                        .foregroundStyle(SwipeTheme.bodyText)
                }
                ReviewUpdatedDate(date: review.updatedAt)
                if let visitedAt = review.visitedAt {
                    Text("来店日：\(visitedAt.formatted(date: .long, time: .omitted))")
                        .font(SwipeTheme.text(12, relativeTo: .caption))
                        .foregroundStyle(SwipeTheme.secondaryText)
                }
                if !review.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(review.photos, id: \.self) { source in
                                Group {
                                    if let image = photoLoader.image(for: source) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                    } else {
                                        SwipeTheme.field
                                    }
                                }
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onAppear { photoLoader.load(source) }
                            }
                        }
                    }
                    .accessibilityLabel("\(review.friendName)さんの写真\(review.photos.count)枚")
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(SwipeTheme.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}
