import SwiftUI

@main
struct MeshinowaApp: App {
    @StateObject private var saved = SavedRestaurantStore()
    @StateObject private var reviews = LocalReviewStore()
    @AppStorage("hasOpenedMeshinowa") private var hasOpened = false
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
        }
    }
}
