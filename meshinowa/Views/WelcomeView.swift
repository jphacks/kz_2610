import SwiftUI

/// 共通の配色とカードを確認する、開発初期の歓迎画面。
struct WelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("BrandIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 116, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .paperCard(radius: 28, shadowOffset: 5)
                    .accessibilityHidden(true)

                Text("meshinowa")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))

                Text("おいしい店は、友達が知っている。")
                    .font(.headline)

                Text("友達が評価したお店が、そのまま地図になる。知らない人の星より、友達のおすすめで選べます。")
                    .font(.body)
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                    .lineSpacing(6)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .paperCard()
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.vertical, 48)
        .foregroundStyle(MeshinowaTheme.ink)
        .background(MeshinowaTheme.paper.ignoresSafeArea())
    }
}

#Preview {
    WelcomeView()
        .preferredColorScheme(.light)
}
