import SwiftUI

private struct PaperCard: ViewModifier {
    var radius: CGFloat
    var shadowOffset: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .background(shape.fill(MeshinowaTheme.card))
            .overlay(shape.strokeBorder(MeshinowaTheme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(shadowOffset > 0 ? 0.06 : 0), radius: shadowOffset * 2, y: shadowOffset / 2)
    }
}

extension View {
    /// 呼び出し側で余白を指定してから適用する。shadowOffset は影の強さとして使う。
    func paperCard(radius: CGFloat = 16, shadowOffset: CGFloat = 3) -> some View {
        modifier(PaperCard(radius: radius, shadowOffset: shadowOffset))
    }
}

/// 淡い色の小さなタグ。緑は友達、からし色は自分の記録に使う。
struct SoftTag: View {
    enum Tone { case mint, mustard, like, neutral }

    let text: String
    var tone: Tone = .mint
    var compact = false

    var body: some View {
        Text(text)
            .font(MeshinowaFont.text(compact ? 11 : 13, weight: compact ? .bold : .medium, relativeTo: .caption))
            .lineLimit(1)
            .padding(.horizontal, compact ? 5 : 10)
            .padding(.vertical, compact ? 1 : 4)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous))
    }

    private var foreground: Color {
        switch tone {
        case .mint: return MeshinowaTheme.mintInk
        case .mustard: return MeshinowaTheme.mustardInk
        case .like: return MeshinowaTheme.likeInk
        case .neutral: return MeshinowaTheme.bodyText
        }
    }

    private var background: Color {
        switch tone {
        case .mint: return MeshinowaTheme.mint
        case .mustard: return MeshinowaTheme.mustardSoft
        case .like: return MeshinowaTheme.likeSoft
        case .neutral: return MeshinowaTheme.field
        }
    }
}

/// 下線で選択中を示すタブ。
struct UnderlineTabs<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        var badge: String? = nil
    }

    let items: [Item]
    @Binding var selection: Value
    var spacing: CGFloat = 26

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items, id: \.value) { item in
                let isSelected = item.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = item.value }
                } label: {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .font(isSelected ? MeshinowaFont.text(16, weight: .bold) : MeshinowaFont.text(16))
                        if let badge = item.badge {
                            Text(badge)
                                .font(MeshinowaFont.number(15, relativeTo: .body))
                                .foregroundStyle(MeshinowaTheme.secondaryText)
                        }
                    }
                    .foregroundStyle(isSelected ? MeshinowaTheme.ink : MeshinowaTheme.secondaryText)
                    .frame(minHeight: 48)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(isSelected ? MeshinowaTheme.ink : .clear)
                            .frame(height: 3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MeshinowaTheme.hairline).frame(height: 1)
        }
    }
}

/// 友達のアバター。初期アイコンはお椀、色は友達ごとに固定する。
struct FriendAvatar: View {
    let name: String
    var size: CGFloat = 26
    var ringed = false
    var symbol: String? = nil

    private static let tones: [Color] = [
        Color(red: 0.95, green: 0.79, blue: 0.66), Color(red: 0.75, green: 0.85, blue: 0.93),
        Color(red: 0.91, green: 0.84, blue: 0.60), Color(red: 0.91, green: 0.76, blue: 0.82),
        Color(red: 0.80, green: 0.88, blue: 0.78), Color(red: 0.86, green: 0.82, blue: 0.93)
    ]

    var body: some View {
        let index = name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.tones.count
        Group {
            if symbol == "person.fill" {
                BowlMark(size: size * 0.8, holes: Self.tones[index])
            } else if let symbol { Image(systemName: symbol) }
            else { Text(String(name.prefix(1))) }
        }
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(MeshinowaTheme.ink)
            .frame(width: size, height: size)
            .background(Self.tones[index], in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: ringed ? 1.5 : 0))
            .accessibilityHidden(true)
    }
}

/// 重ねて並べるアバター。
struct FriendAvatarStack: View {
    let names: [String]
    var size: CGFloat = 22
    var limit = 3

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { _, name in
                FriendAvatar(name: name, size: size, ringed: true)
            }
        }
    }
}

/// お椀とお箸のロゴ。輪の右上の小さな丸2つは、輪をくり抜いた穴として背景の色で描く。
struct BowlMark: View {
    var size: CGFloat = 24
    var ring: Color = MeshinowaTheme.green
    /// 穴の色。置く場所の背景に合わせる。
    var holes: Color = MeshinowaTheme.paper

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 200
            let circle = Path(ellipseIn: CGRect(x: 50 * s, y: 50 * s, width: 98 * s, height: 98 * s))
            context.stroke(circle, with: .color(ring), lineWidth: 22 * s)
            for center in [CGPoint(x: 120, y: 52), CGPoint(x: 133, y: 61)] {
                let r: CGFloat = 3.8
                context.fill(Path(ellipseIn: CGRect(x: (center.x - r) * s, y: (center.y - r) * s,
                                                    width: 2 * r * s, height: 2 * r * s)), with: .color(holes))
            }
            var sticks = Path()
            sticks.move(to: CGPoint(x: 55 * s, y: 43 * s)); sticks.addLine(to: CGPoint(x: 167 * s, y: 115 * s))
            sticks.move(to: CGPoint(x: 45 * s, y: 59 * s)); sticks.addLine(to: CGPoint(x: 161 * s, y: 131 * s))
            context.stroke(sticks, with: .color(MeshinowaTheme.accent),
                           style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// アプリアイコンと同じ、緑の丸に白い輪のロゴ。
struct BowlBadge: View {
    var size: CGFloat = 56

    var body: some View {
        Circle()
            .fill(MeshinowaTheme.green)
            .overlay {
                BowlMark(size: size * 0.78, ring: MeshinowaTheme.cream, holes: MeshinowaTheme.green)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 写真がまだないお店の見出し画像。ジャンルのアイコンを淡く置く。
struct PhotoPlaceholder: View {
    var symbol = "fork.knife"
    var tint: Color = MeshinowaTheme.photo
    var cornerRadius: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tint)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(MeshinowaTheme.mustardInk.opacity(0.35))
            }
            .accessibilityHidden(true)
    }
}

/// アイコン付きの情報行。
struct InfoRow<Trailing: View>: View {
    let symbol: String
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(MeshinowaFont.text(15))
                .foregroundStyle(MeshinowaTheme.bodyText)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            trailing()
        }
        .foregroundStyle(MeshinowaTheme.ink)
    }
}

extension InfoRow where Trailing == EmptyView {
    init(symbol: String, text: String) {
        self.init(symbol: symbol, text: text) { EmptyView() }
    }
}

/// 画面上部の大きな見出し。
struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(MeshinowaFont.heading(28, relativeTo: .largeTitle))
            .foregroundStyle(MeshinowaTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 地図と保存の写真に掛けるジャンルの札。分類できないお店には出さない。
struct GenreRibbon: View {
    let genre: FoodGenre
    var compact = false

    var body: some View {
        if genre != .other {
            VStack(spacing: compact ? 2 : 3) {
                ForEach(Array(genre.title.enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(MeshinowaFont.wa(compact ? 12 : 14))
                }
            }
            .foregroundStyle(MeshinowaTheme.paper)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.top, compact ? 8 : 10)
            .padding(.bottom, compact ? 10 : 12)
            .background(MeshinowaTheme.green, in: UnevenRoundedRectangle(
                bottomLeadingRadius: compact ? 5 : 6, bottomTrailingRadius: compact ? 5 : 6))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(genre.title)
        }
    }
}

/// 保存の写真に重ねる、自分の評価だけの小さな判子。
struct CompactRatingSeal: View {
    let rating: Double

    var body: some View {
        VStack(spacing: 0) {
            Text(rating, format: .number.precision(.fractionLength(1)))
                .font(MeshinowaFont.number(16, relativeTo: .caption))
            Text("自分").font(MeshinowaFont.wa(8)).tracking(2)
        }
        .foregroundStyle(MeshinowaTheme.mustardInk)
        .frame(width: 46, height: 46)
        .background(MeshinowaTheme.cream, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(MeshinowaTheme.accent, lineWidth: 3))
        .rotationEffect(.degrees(-6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("自分の評価、\(rating.formatted(.number.precision(.fractionLength(1))))点")
    }
}

/// 地図カードの3つの操作。状態は色と文字の両方で示す。
struct RestaurantActionTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let background: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 22)).accessibilityHidden(true)
            Text(title).font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
