import SwiftUI

@main
struct MeshinowaApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WelcomeView()
            }
            .tint(MeshinowaTheme.green)
            .preferredColorScheme(.light)
        }
    }
}
