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

/// 実際の地図のピン。小さな丸に記号だけを置き、選ぶと大きな丸になる。
/// いいねはピンク、レビューしたお店は緑に自分の点数を出し、地図を見ただけで自分の記録が分かるようにする。
/// 先端は丸の縁と同じ色にして、縁から先端までひと続きに見せる。
struct PlacePin: View {
    enum Mark: Equatable { case none, liked, reviewed(Double) }

    let symbol: String
    var mark: Mark = .none
    /// レビューしたお店にいいねも付いているとき、右上に小さなハートを添える。
    var showsLikeBadge = false
    var isSelected = false

    private var fill: Color {
        // いいねのピンは選択中もピンクのまま。大きさで選択中を示す。
        if isSelected && mark != .liked { return MeshinowaTheme.green }
        switch mark {
        case .none: return MeshinowaTheme.card
        case .liked: return MeshinowaTheme.like
        case .reviewed: return MeshinowaTheme.green
        }
    }

    @ViewBuilder private var content: some View {
        switch mark {
        case .none:
            Image(systemName: symbol)
                .font(.system(size: isSelected ? 17 : 10, weight: .bold))
        case .liked:
            Image(systemName: "heart.fill")
                .font(.system(size: isSelected ? 17 : 10, weight: .bold))
        case .reviewed(let score):
            Text(score, format: .number.precision(.fractionLength(1)))
                .font(MeshinowaFont.number(isSelected ? 16 : 11, relativeTo: .caption))
                .padding(.horizontal, isSelected ? 6 : 4)
        }
    }

    var body: some View {
        let isPlain = !isSelected && mark == .none
        let rim = isPlain ? MeshinowaTheme.green : Color.white
        VStack(spacing: -1) {
            // 点数のピンは横に広がれるようカプセルにする。幅と高さが同じときは丸になる。
            content
                .frame(minWidth: isSelected ? 42 : 24, minHeight: isSelected ? 42 : 24)
                .fixedSize()
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(rim, lineWidth: isPlain ? 1.5 : (isSelected ? 3 : 2)))
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
            .foregroundStyle(isPlain ? MeshinowaTheme.green : .white)
            PinTail()
                .fill(rim)
                .frame(width: isSelected ? 14 : 8, height: isSelected ? 8 : 5)
        }
        .shadow(color: .black.opacity(isSelected ? 0.3 : 0.22), radius: isSelected ? 6 : 3, y: isSelected ? 3 : 1.5)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isSelected)
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
            PlacePin(symbol: "fork.knife")
            PlacePin(symbol: "cup.and.saucer.fill", mark: .liked)
            PlacePin(symbol: "birthday.cake.fill", mark: .reviewed(4.5), showsLikeBadge: true)
            PlacePin(symbol: "fork.knife", isSelected: true)
        }
    }
    .padding(32)
    .preferredColorScheme(.light)
}
