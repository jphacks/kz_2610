import SwiftUI

/// デザイン確定前の、最初の歓迎画面。
struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("meshinowa")
                .font(.largeTitle.bold())

            Text("おいしい店は、友達が知っている。")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WelcomeView()
}
