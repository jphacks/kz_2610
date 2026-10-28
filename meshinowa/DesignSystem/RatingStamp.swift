import SwiftUI

/// 友達の平均点。店名の右に置く。
struct RatingStamp: View {
    let rating: Double?
    let friendCount: Int
    var size: CGFloat = 22

    private var hasRating: Bool {
        rating != nil && friendCount > 0
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let rating, hasRating {
                Text(rating, format: .number.precision(.fractionLength(1)))
                    .font(MeshinowaFont.number(size))
                    .foregroundStyle(MeshinowaTheme.green)
                Text("友達\(friendCount)人")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
            } else {
                Text("—")
                    .font(MeshinowaFont.number(size))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                Text("未評価")
                    .font(MeshinowaFont.text(12, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
            }
        }
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

/// 地図上のピン。白い箱に点数と小さなタグ。選択中はブランドの緑になる。
struct ScorePin: View {
    let title: String
    var tag: String? = nil
    var tagTone: SoftTag.Tone = .mint
    var isSelected = false
    var symbol: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)
            } else {
                Text(title)
                    .font(MeshinowaFont.number(16, relativeTo: .body))
            }
            if let tag {
                SoftTag(text: tag, tone: tagTone, compact: true)
            }
        }
        .foregroundStyle(isSelected ? Color.white : MeshinowaTheme.ink)
        .padding(.horizontal, symbol == nil ? 7 : 6)
        .padding(.top, symbol == nil ? 6 : 6)
        .padding(.bottom, symbol == nil ? 5 : 6)
        .frame(minWidth: symbol == nil ? 40 : 28, minHeight: symbol == nil ? 40 : 28)
        .background(isSelected ? MeshinowaTheme.green : MeshinowaTheme.card,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isSelected ? MeshinowaTheme.green : MeshinowaTheme.outline, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .scaleEffect(isSelected ? (symbol == nil ? 1.08 : 1.3) : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

/// 実際の地図のピン。形はジャンルの器（お椀・丼・提灯など）、色は自分の記録。
/// 記録なしは白に緑の線、いいねはピンクにハート、自分が評価したお店はからし色に自分の点数、
/// 友達だけが評価したお店は緑に友達の平均点。選ぶと大きくなる。
/// 形は output/wa-design/category-pins.html のデザインと同じ。
struct PlacePin: View {
    enum Mark: Equatable {
        case none, liked
        /// 自分の評価。からし色。
        case reviewed(Double)
        /// 友達の平均点。緑。
        case friends(Double)
    }

    /// 以前の丸いピンのアイコン。今は形をジャンルで決めるため使わない。
    var symbol: String = "fork.knife"
    var genre: FoodGenre = .other
    var mark: Mark = .none
    /// レビューしたお店にいいねも付いているとき、右上に小さなハートを添える。
    var showsLikeBadge = false
    var isSelected = false

    private var tone: FoodGenreMark.Tone {
        switch mark {
        // いいねのピンは選択中もピンクのまま。大きさで選択中を示す。
        case .liked: return .liked
        case .reviewed: return .mine
        case .friends: return .reviewed
        case .none: return isSelected ? .reviewed : .plain
        }
    }

    private var width: CGFloat { isSelected ? 50 : 32 }

    @ViewBuilder private var content: some View {
        switch mark {
        case .none:
            EmptyView()
        case .liked:
            Image(systemName: "heart.fill")
                .font(.system(size: isSelected ? 14 : 9, weight: .bold))
        case .reviewed(let score), .friends(let score):
            Text(score, format: .number.precision(.fractionLength(1)))
                .font(MeshinowaFont.number(isSelected ? 15 : 10, relativeTo: .caption))
                .fixedSize()
        }
    }

    var body: some View {
        let anchor = FoodGenreMark.contentAnchor(for: genre)
        let tailColor: Color = switch tone {
        case .liked: MeshinowaTheme.like
        case .mine: MeshinowaTheme.accent
        default: MeshinowaTheme.green
        }
        // からし色の上は白い文字が読みにくいので、自分の評価の文字色にする。
        let contentColor = tone == .mine ? MeshinowaTheme.mustardInk : Color.white
        VStack(spacing: -1) {
            FoodGenreMark(genre: genre, tone: tone, size: width)
                .overlay {
                    GeometryReader { proxy in
                        content
                            .foregroundStyle(contentColor)
                            .position(x: proxy.size.width * anchor.x, y: proxy.size.height * anchor.y)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showsLikeBadge {
                        Image(systemName: "heart.fill")
                            .font(.system(size: isSelected ? 9 : 7, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: isSelected ? 18 : 14, height: isSelected ? 18 : 14)
                            .background(Circle().fill(MeshinowaTheme.like))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .offset(x: 5, y: -5)
                    }
                }
            PinTail()
                .fill(tailColor)
                .frame(width: isSelected ? 12 : 8, height: isSelected ? 8 : 6)
        }
        .shadow(color: .black.opacity(isSelected ? 0.3 : 0.22), radius: isSelected ? 6 : 3, y: isSelected ? 3 : 1.5)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isSelected)
        .accessibilityHidden(true)
    }
}

private struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

#Preview("評価とピン") {
    VStack(spacing: 24) {
        HStack(spacing: 24) {
            RatingStamp(rating: 4.7, friendCount: 3)
            RatingStamp(rating: nil, friendCount: 0)
        }
        HStack(spacing: 16) {
            ScorePin(title: "4.7", tag: "友達3")
            ScorePin(title: "4.5", tag: "いいね", tagTone: .mustard)
            ScorePin(title: "4.8", tag: "友達2", isSelected: true)
        }
        HStack(spacing: 16) {
            PlacePin(genre: .noodle)
            PlacePin(genre: .cafe, mark: .liked)
            PlacePin(genre: .bread, mark: .reviewed(4.5), showsLikeBadge: true)
            PlacePin(genre: .washoku, mark: .friends(4.2))
            PlacePin(genre: .izakaya, isSelected: true)
        }
    }
    .padding(32)
    .preferredColorScheme(.light)
}
