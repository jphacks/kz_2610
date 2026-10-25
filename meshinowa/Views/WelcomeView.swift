import SwiftUI

/// 共通の配色とカードを確認する、開発初期の歓迎画面。
struct WelcomeView: View {
    var onStart: (() -> Void)? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BowlMark(size: 72)
                    .padding(.bottom, 28)
                Text("meshinowa")
                    .font(MeshinowaFont.heading(16))
                    .foregroundStyle(MeshinowaTheme.green)
                Text("おいしい店は、\n友達が知っている。")
                    .font(MeshinowaFont.heading(32, relativeTo: .largeTitle))
                    .lineSpacing(4)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
                Text("友達が評価したお店が、そのまま地図になる。知らない人の星より、友達のおすすめで選べます。")
                    .font(MeshinowaFont.text(16))
                    .foregroundStyle(MeshinowaTheme.bodyText)
                    .lineSpacing(6)
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 10) {
                    point("map", "地図でお店を探して、気になる店にいいね")
                    point("star.bubble", "行ったお店は星とひとことで記録")
                    point("person.2", "友達の評価だけで点数を出す")
                }
                .padding(.top, 28)
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 72)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Group {
                    if let onStart {
                        Button("マップを開く", action: onStart)
                    } else {
                        NavigationLink("マップを開く") { MapHomeView() }
                    }
                }
                .buttonStyle(PaperButtonStyle())

                NavigationLink {
                    DemoRecommendationsView()
                } label: {
                    Text("架空データで友達の評価を試す")
                }
                .buttonStyle(PaperButtonStyle(kind: .secondary))
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(MeshinowaTheme.paper)
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .background(MeshinowaTheme.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MeshinowaTheme.green)
                .frame(width: 34, height: 34)
                .background(MeshinowaTheme.mint, in: Circle())
                .accessibilityHidden(true)
            Text(text).font(MeshinowaFont.text(15))
        }
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
    .preferredColorScheme(.light)
    .environmentObject(SavedRestaurantStore())
    .environmentObject(LocalReviewStore())
}
