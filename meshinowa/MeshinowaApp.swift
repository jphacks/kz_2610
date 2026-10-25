import SwiftUI

@main
struct MeshinowaApp: App {
    @StateObject private var saved = SavedRestaurantStore()
    @StateObject private var reviews = LocalReviewStore()
    @StateObject private var friends = FriendStore(presentation: PresentationDemo.dataset)
    @AppStorage("hasOpenedMeshinowa") private var hasOpened = false
    @AppStorage("hasSeededKITPresentation") private var hasSeededPresentation = false
    @AppStorage("hasRemovedKITPersonalSamples") private var hasRemovedPersonalSamples = false
    @State private var demoError: String?
    init() { GooglePlacesService.configure() }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasOpened || PresentationDemo.isEnabled {
                    MainTabView()
                } else {
                    NavigationStack {
                        WelcomeView(onStart: { hasOpened = true })
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if PresentationDemo.isEnabled {
                    HStack {
                        Text("発表デモ · 友達のコメント・評価はモック")
                        Spacer(minLength: 4)
                        Button("友達を戻す") { friends.resetPresentation() }
                            .accessibilityLabel("友達のモックだけを初期状態に戻す")
                    }
                    .font(MeshinowaFont.text(11, weight: .bold))
                    .foregroundStyle(MeshinowaTheme.mintInk)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(MeshinowaTheme.mint)
                }
            }
            .tint(MeshinowaTheme.green)
            .preferredColorScheme(.light)
            .alert("発表データを準備できませんでした", isPresented: Binding(get: { demoError != nil }, set: { if !$0 { demoError = nil } })) {
                Button("再試行") { removePersonalSamples() }
            } message: { Text(demoError ?? "") }
            .environmentObject(saved)
            .environmentObject(reviews)
            .environmentObject(friends)
            .task {
                reviews.onSaved = { review in Task { try? await friends.upload(review) } }
                reviews.onDeleted = { restaurant in Task { try? await friends.removeReview(for: restaurant) } }
                // テスト実行時はアプリ本体からサーバーへ接続しない。
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                if PresentationDemo.isEnabled && hasSeededPresentation && !hasRemovedPersonalSamples { removePersonalSamples() }
                await friends.start(sharing: reviews.reviews)
            }
        }
    }

    @MainActor private func removePersonalSamples() {
        do {
            try PresentationDemo.removeLegacyPersonalSamples(saved: saved, reviews: reviews)
            hasRemovedPersonalSamples = true
        } catch { demoError = error.localizedDescription }
    }
}
