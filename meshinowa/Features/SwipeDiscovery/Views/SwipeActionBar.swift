import SwiftUI

/// 下部のボタン。左から「戻す（↺）」「イマイチ（渦巻き）」「行きたい（旗）」（v5で紙飛行機を外して3つ）。
struct SwipeActionBar: View {
    let canUndo: Bool
    let isEnabled: Bool
    let onUndo: () -> Void
    let onDecide: (SwipeDecisionKind) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            button(title: "戻す", symbol: "arrow.uturn.backward", tint: SwipeTheme.undo, size: 52, filled: false,
                   hint: "直前の判断を取り消します", action: onUndo)
                .disabled(!canUndo)
            button(title: "イマイチ", symbol: "hurricane", tint: SwipeTheme.notInterested, size: 64, filled: true,
                   hint: "24時間はこのお店を出しません") { onDecide(.notInterested) }
                .disabled(!isEnabled)
            button(title: "行きたい", symbol: "flag.fill", tint: SwipeTheme.interested, size: 64, filled: true,
                   hint: "行きたいに保存します") { onDecide(.interested) }
                .disabled(!isEnabled)
        }
        .frame(maxWidth: .infinity)
    }

    private func button(title: String, symbol: String, tint: Color, size: CGFloat, filled: Bool,
                        hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(filled ? Color.white : tint)
                    .frame(width: size, height: size)
                    .background(Circle().fill(filled ? tint : SwipeTheme.card))
                    .overlay(Circle().strokeBorder(filled ? Color.clear : SwipeTheme.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                Text(title)
                    .font(SwipeTheme.text(12, bold: true, relativeTo: .caption))
                    .foregroundStyle(tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SwipeActionButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

private struct SwipeActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
