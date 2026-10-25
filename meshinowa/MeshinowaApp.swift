import SwiftUI

@main
struct MeshinowaApp: App {
    @StateObject private var saved: SavedRestaurantStore
    @StateObject private var reviews: LocalReviewStore
    @StateObject private var friends = FriendStore(backend: ProcessInfo.processInfo.environment["MESHINOWA_OFFLINE"] == "1" ? nil : try? CloudflareBackend.makeClient())
    @StateObject private var transfer = LibraryTransfer()
    @StateObject private var location = LocationStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasOpenedMeshinowa") private var hasOpened = false
    private let preferenceStore: UserDefaults
    init() {
        if let testID = ProcessInfo.processInfo.environment["MESHINOWA_UI_TEST_ID"], UUID(uuidString: testID) != nil {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meshinowa-ui-" + testID)
            _saved = StateObject(wrappedValue: SavedRestaurantStore(fileURL: directory.appendingPathComponent("saved.json")))
            _reviews = StateObject(wrappedValue: LocalReviewStore(fileURL: directory.appendingPathComponent("reviews.json")))
            preferenceStore = UserDefaults(suiteName: "jp.meshinowa.ui-tests." + testID)!
        } else {
            _saved = StateObject(wrappedValue: SavedRestaurantStore())
            _reviews = StateObject(wrappedValue: LocalReviewStore())
            preferenceStore = .standard
        }
        GooglePlacesService.configure()
    }

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
            .defaultAppStorage(preferenceStore)
            .disabled(transfer.isBusy)
            .tint(MeshinowaTheme.green)
            .preferredColorScheme(.light)
            .environmentObject(saved)
            .environmentObject(reviews)
            .environmentObject(friends)
            .environmentObject(transfer)
            .environmentObject(location)
            .alert("操作を完了できませんでした", isPresented: Binding(get: { friends.actionError != nil }, set: { if !$0 { friends.actionError = nil } })) {
                Button("閉じる", role: .cancel) { friends.actionError = nil }
            } message: { Text(friends.actionError ?? "") }
            .task {
                friends.connect(to: reviews)
                transfer.connect(saved: saved, reviews: reviews, friends: friends)
                reviews.onSaved = { _ in Task { await friends.flushReviews() } }
                reviews.onDeleted = { _ in Task { await friends.flushReviews() } }
                // テスト実行時はアプリ本体からサーバーへ接続しない。
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                if friends.needsLocalReset {
                    do {
                        try reviews.clear(); try saved.clear()
                        friends.finishLocalReset()
                    } catch {
                        friends.actionError = "アカウント削除後の端末の初期化を完了できませんでした。設定から再試行してください。"
                        return
                    }
                }
                await friends.start(sharing: reviews.reviews)
            }
            .task(id: scenePhase) {
                guard scenePhase == .active,
                      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                while !Task.isCancelled {
                    await friends.flushReviews()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
        }
    }
}
