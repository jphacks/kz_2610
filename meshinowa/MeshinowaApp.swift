import SwiftUI

@main
struct MeshinowaApp: App {
    @StateObject private var saved = SavedRestaurantStore()
    @StateObject private var reviews = LocalReviewStore()
    @StateObject private var friends = FriendStore(presentation: PresentationDemo.dataset)
    @AppStorage("hasOpenedMeshinowa") private var hasOpened = false
    @AppStorage("hasSeededKITPresentation") private var hasSeededPresentation = false
    @State private var demoError: String?
    @State private var confirmsDemoReset = false
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
                        Text("発表デモ · 友達・レビューは架空です")
                        Spacer(minLength: 4)
                        Button("初期化") { confirmsDemoReset = true }
                            .accessibilityLabel("発表用の記録を初期化")
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
            .confirmationDialog("発表用の記録を初期状態に戻しますか？", isPresented: $confirmsDemoReset, titleVisibility: .visible) {
                Button("発表データを初期化", role: .destructive) { preparePresentation(reset: true) }
            }
            .alert("発表データを準備できませんでした", isPresented: Binding(get: { demoError != nil }, set: { if !$0 { demoError = nil } })) {
                Button("再試行") { preparePresentation(reset: false) }
            } message: { Text(demoError ?? "") }
            .environmentObject(saved)
            .environmentObject(reviews)
            .environmentObject(friends)
            .task {
                reviews.onSaved = { review in Task { try? await friends.upload(review) } }
                reviews.onDeleted = { restaurant in Task { try? await friends.removeReview(for: restaurant) } }
                // テスト実行時はアプリ本体からサーバーへ接続しない。
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                if PresentationDemo.isEnabled && !hasSeededPresentation { preparePresentation(reset: false) }
                await friends.start(sharing: reviews.reviews)
            }
        }
    }

    @MainActor private func preparePresentation(reset: Bool) {
        guard PresentationDemo.isEnabled else { return }
        do {
            if reset {
                for review in reviews.reviews { try reviews.delete(id: review.id) }
                for restaurant in saved.restaurants {
                    guard saved.setLiked(restaurant.mapItem, isLiked: false) else { throw CocoaError(.fileWriteUnknown) }
                }
                friends.resetPresentation()
            }
            try PresentationDemo.seedPersonalRecords(saved: saved, reviews: reviews)
            hasSeededPresentation = true
        } catch { demoError = error.localizedDescription }
    }

}
