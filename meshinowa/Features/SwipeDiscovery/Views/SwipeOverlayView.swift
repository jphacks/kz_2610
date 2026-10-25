import SwiftUI

/// ドラッグ中に判断内容を示す色付きのオーバーレイ。色だけで伝えず、アイコンと文字を併記する。
struct SwipeOverlayView: View {
    let kind: SwipeDecisionKind
    let opacity: Double

    var body: some View {
        ZStack {
            color.opacity(opacity)
            VStack(spacing: 12) {
                Image(systemName: kind == .interested ? "flag.fill" : "hurricane")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 92, height: 92)
                    .background(.white, in: Circle())
                Text(kind == .interested ? "行きたい！" : "イマイチ…")
                    .font(SwipeTheme.heading(30, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white, lineWidth: 3))
                    .rotationEffect(.degrees(kind == .interested ? -8 : 8))
            }
            .opacity(min(1, opacity / SwipeGestureConstants.maxOverlayOpacity))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var color: Color { kind == .interested ? SwipeTheme.interested : SwipeTheme.notInterested }
}
