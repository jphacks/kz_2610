import SwiftUI

struct PaperButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        /// 自分が登録済みの状態。からし色で示す。
        case selected
        /// いいね済み。ピンクで示す。
        case liked
    }

    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        configuration.label
            .font(MeshinowaFont.heading(16))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(foreground)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(kind == .secondary ? MeshinowaTheme.outline : Color.clear, lineWidth: 1))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return MeshinowaTheme.ink
        case .selected: return MeshinowaTheme.mustardInk
        case .liked: return MeshinowaTheme.likeInk
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return MeshinowaTheme.green
        case .secondary: return MeshinowaTheme.card
        case .selected: return MeshinowaTheme.mustardSoft
        case .liked: return MeshinowaTheme.likeSoft
        }
    }
}

/// 枠線だけの丸いフィルター。選ぶと線が太くなる。
struct PillButtonStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isOn ? MeshinowaFont.text(14, weight: .bold) : MeshinowaFont.text(14))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .foregroundStyle(MeshinowaTheme.ink)
            .background(Capsule().fill(MeshinowaTheme.card))
            .overlay(Capsule().strokeBorder(isOn ? MeshinowaTheme.ink : MeshinowaTheme.outline,
                                            lineWidth: isOn ? 2 : 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 写真の上や地図の上に置く丸いアイコンボタン。
struct CircleIconButtonStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(filled ? Color.white : MeshinowaTheme.ink)
            .background(Circle().fill(filled ? MeshinowaTheme.ink.opacity(0.45) : MeshinowaTheme.card))
            .shadow(color: .black.opacity(filled ? 0 : 0.14), radius: 4, y: 1)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview("共通ボタン") {
    VStack(spacing: 20) {
        Button("主ボタン") {}
            .buttonStyle(PaperButtonStyle())
        Button("副ボタン") {}
            .buttonStyle(PaperButtonStyle(kind: .secondary))
        Button("無効なボタン") {}
            .buttonStyle(PaperButtonStyle())
            .disabled(true)
        HStack {
            Button("カフェ") {}.buttonStyle(PillButtonStyle(isOn: true))
            Button("ベーカリー") {}.buttonStyle(PillButtonStyle())
        }
    }
    .padding(24)
}
