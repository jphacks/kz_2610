import SwiftUI

struct RatingStamp: View {
    let rating: Double?
    let friendCount: Int

    @ScaledMetric(relativeTo: .title2) private var diameter = 76.0

    private var hasRating: Bool {
        rating != nil && friendCount > 0
    }

    var body: some View {
        VStack(spacing: 2) {
            if let rating, hasRating {
                Text(rating, format: .number.precision(.fractionLength(1)))
                    .font(MeshinowaFont.number(27))
                Text("友達\(friendCount)人")
                    .font(MeshinowaFont.text(9, weight: .black, relativeTo: .caption2))
            } else {
                Text("—")
                    .font(MeshinowaFont.number(27))
                Text("未評価")
                    .font(MeshinowaFont.text(9, weight: .black, relativeTo: .caption2))
            }
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .frame(width: diameter, height: diameter)
        .background(Circle().fill(MeshinowaTheme.accent))
        .overlay(Circle().strokeBorder(MeshinowaTheme.ink, lineWidth: 2))
        .rotationEffect(.degrees(-8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let rating, hasRating else {
            return "友達の評価はまだありません"
        }
        let value = rating.formatted(.number.precision(.fractionLength(1)))
        return "友達\(friendCount)人の評価、5点満点中\(value)点"
    }
}

#Preview("評価あり・未評価") {
    HStack(spacing: 24) {
        RatingStamp(rating: 4.7, friendCount: 3)
        RatingStamp(rating: nil, friendCount: 0)
    }
    .padding(32)
    .background(MeshinowaTheme.paper)
    .preferredColorScheme(.light)
}
