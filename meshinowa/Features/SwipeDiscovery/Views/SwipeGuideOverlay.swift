import SwiftUI

/// カードの下（カードと下部ボタンの間）に出す、灰色の左向き矢印とピンクの右向き矢印（F-21・F-22）。
/// 文字は付けず、真下の同じ色のボタンと色で対応させる。タップは受け取らず、読み上げ対象にもしない。
struct SwipeGuideOverlay: View {
    /// 矢印が消えてもレイアウトがずれないよう、この高さは常に確保する。
    static let height: CGFloat = 28

    let mode: SwipeGuideMode
    /// ドラッグ中の横移動量（0 ならドラッグしていない）。
    let dragX: CGFloat
    /// お手本の動きでカードが動いている向き（-1 左、0 なし、1 右）。
    var demoDirection: Int = 0
    var isVisible = true

    var body: some View {
        let opacities = SwipeGuidePolicy.arrowOpacities(mode: mode, dragX: dragX)
        HStack {
            SwipeGuideArrow(pointsRight: false)
                .stroke(SwipeTheme.notInterested, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .frame(width: 56, height: 16)
                .scaleEffect(demoDirection < 0 ? SwipeGuidePolicy.demoEmphasisScale : 1)
                .opacity(opacities.left)
            Spacer()
            SwipeGuideArrow(pointsRight: true)
                .stroke(SwipeTheme.interested, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .frame(width: 56, height: 16)
                .scaleEffect(demoDirection > 0 ? SwipeGuidePolicy.demoEmphasisScale : 1)
                .opacity(opacities.right)
        }
        .padding(.horizontal, 24)
        .frame(height: Self.height)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: dragX > 0)
        .animation(.easeOut(duration: 0.2), value: dragX < 0)
        .animation(.easeInOut(duration: 0.3), value: demoDirection)
        .animation(.easeOut(duration: 0.3), value: isVisible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 線端の丸い矢印（長さ約56pt）。
struct SwipeGuideArrow: Shape {
    let pointsRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        let head = min(rect.height / 2, 8)
        if pointsRight {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            path.move(to: CGPoint(x: rect.maxX - head, y: y - head))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX - head, y: y + head))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: y))
            path.addLine(to: CGPoint(x: rect.minX, y: y))
            path.move(to: CGPoint(x: rect.minX + head, y: y - head))
            path.addLine(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.minX + head, y: y + head))
        }
        return path
    }
}
