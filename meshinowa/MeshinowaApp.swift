import SwiftUI

@main
struct MeshinowaApp: App {
    @StateObject private var saved = SavedRestaurantStore()
    @StateObject private var reviews = LocalReviewStore()
    @StateObject private var friends = FriendStore()
    @AppStorage("hasOpenedMeshinowa") private var hasOpened = false
    init() { GooglePlacesService.configure() }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasOpened {
                    MainTabView()
                } else {
                    NavigationStack {
                        WelcomeView(onStart: { hasOpened = true })
                    }
                }
            }
            .tint(MeshinowaTheme.green)
            .preferredColorScheme(.light)
            .environmentObject(saved)
            .environmentObject(reviews)
            .environmentObject(friends)
            .task {
                reviews.onSaved = { review in Task { try? await friends.upload(review) } }
                reviews.onDeleted = { restaurant in Task { try? await friends.removeReview(for: restaurant) } }
                // テスト実行時はアプリ本体からサーバーへ接続しない。
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                await friends.start(sharing: reviews.reviews)
            }
        }
    }
}
