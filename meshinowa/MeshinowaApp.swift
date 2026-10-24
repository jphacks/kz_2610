import SwiftUI

@main
struct MeshinowaApp: App {
    @StateObject private var saved = SavedRestaurantStore()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WelcomeView()
            }
            .tint(MeshinowaTheme.green)
            .preferredColorScheme(.light)
            .environmentObject(saved)
        }
    }
}
