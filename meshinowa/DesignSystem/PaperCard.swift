import SwiftUI

private struct PaperCard: ViewModifier {
    var radius: CGFloat
    var shadowOffset: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)

        content
            .background(shape.fill(MeshinowaTheme.card))
            .overlay(shape.strokeBorder(MeshinowaTheme.ink, lineWidth: 2))
            .background {
                shape
                    .fill(MeshinowaTheme.ink)
                    .offset(x: shadowOffset, y: shadowOffset)
            }
    }
}

extension View {
    /// 呼び出し側で余白を指定してから適用する。
    func paperCard(radius: CGFloat = 22, shadowOffset: CGFloat = 4) -> some View {
        modifier(PaperCard(radius: radius, shadowOffset: shadowOffset))
    }
}
