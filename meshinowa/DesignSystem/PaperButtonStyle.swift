import SwiftUI

struct PaperButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        let offset: CGFloat = configuration.isPressed ? 1 : 3

        configuration.label
            .font(MeshinowaFont.text(15, weight: .black))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(kind == .primary ? MeshinowaTheme.card : MeshinowaTheme.ink)
            .background(shape.fill(kind == .primary ? MeshinowaTheme.green : MeshinowaTheme.card))
            .overlay(shape.strokeBorder(MeshinowaTheme.ink, lineWidth: 2))
            .background(shape.fill(MeshinowaTheme.ink).offset(x: offset, y: offset))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
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
    }
    .padding(24)
    .background(MeshinowaTheme.paper)
}
