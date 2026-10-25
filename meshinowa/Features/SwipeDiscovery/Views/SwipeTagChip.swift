import SwiftUI

/// カード下部のタグ。#大分類（塗り）・#詳細ジャンル（枠線）・おすすめ料理（グレーのピル型）の3種類。
struct SwipeTagChip: View {
    enum Kind { case category, genre, dish }

    let text: String
    let kind: Kind

    var body: some View {
        Text(kind == .dish ? text : "#" + text)
            .font(SwipeTheme.text(11, bold: kind == .category, relativeTo: .caption2))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(kind == .dish ? SwipeTheme.bodyText : SwipeTheme.tagText)
            .padding(.horizontal, kind == .dish ? 8 : 6)
            .frame(minHeight: 19)
            .background {
                switch kind {
                case .category:
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(SwipeTheme.tagBackground)
                case .genre:
                    RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(SwipeTheme.tagOutline, lineWidth: 1)
                case .dish:
                    Capsule().strokeBorder(SwipeTheme.dishOutline, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

/// タグの行。1行に収め、入りきらない時はおすすめ料理から削って「+2」のように残りの数を出す。
struct SwipeTagRow: View {
    let candidate: SwipeCandidate
    var maxDishes = 3

    private var dishes: [String] { Array(candidate.recommendedDishes.prefix(maxDishes)) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array((0...dishes.count).reversed()), id: \.self) { shown in
                row(dishCount: shown)
            }
            // おすすめ料理を全部削っても入らない時は、詳細ジャンルも削る。
            row(dishCount: 0, showsGenre: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func row(dishCount: Int, showsGenre: Bool = true) -> some View {
        let hidden = candidate.recommendedDishes.count - dishCount
        return HStack(spacing: 4) {
            SwipeTagChip(text: candidate.category.name, kind: .category)
            if showsGenre, let genre = candidate.detailGenre {
                SwipeTagChip(text: genre, kind: .genre)
            }
            ForEach(dishes.prefix(dishCount), id: \.self) { dish in
                SwipeTagChip(text: dish, kind: .dish)
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(SwipeTheme.text(11, bold: true, relativeTo: .caption2))
                    .foregroundStyle(SwipeTheme.secondaryText)
                    .fixedSize()
            }
        }
    }

    /// VoiceOver では # を読ませない（「ジャンル、麺、ラーメン」）。
    private var accessibilityText: String {
        var parts = ["ジャンル", candidate.category.name]
        if let genre = candidate.detailGenre { parts.append(genre) }
        if !candidate.recommendedDishes.isEmpty {
            parts.append("おすすめ料理")
            parts.append(contentsOf: candidate.recommendedDishes)
        }
        return parts.joined(separator: "、")
    }
}
