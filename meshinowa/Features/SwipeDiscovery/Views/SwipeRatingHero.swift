import SwiftUI

/// 写真がない店で、写真の代わりに友達の平均評価を大きく見せる（F-06）。
struct SwipeRatingHero: View {
    let candidate: SwipeCandidate

    var body: some View {
        ZStack {
            SwipeTheme.heroBackground(for: candidate.category)
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(SwipeTheme.star)
                    Text(candidate.averageRating, format: .number.precision(.fractionLength(1)))
                        .font(SwipeTheme.number(48, relativeTo: .largeTitle))
                        .foregroundStyle(SwipeTheme.ink)
                }
                Text("友達\(candidate.reviews.count)人が評価")
                    .font(SwipeTheme.text(15, bold: true))
                    .foregroundStyle(SwipeTheme.bodyText)
                if let comment = candidate.latestComment {
                    Text("「\(comment)」")
                        .font(SwipeTheme.text(14))
                        .foregroundStyle(SwipeTheme.bodyText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }
            .padding(.vertical, 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("友達\(candidate.reviews.count)人の平均 \(candidate.averageRating.formatted(.number.precision(.fractionLength(1))))"
                            + (candidate.latestComment.map { "、\($0)" } ?? ""))
    }
}
