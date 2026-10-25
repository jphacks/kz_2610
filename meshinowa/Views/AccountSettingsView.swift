import SwiftUI

struct SWAccountSettingsView: View {
    @EnvironmentObject private var friends: FriendStore
    @EnvironmentObject private var reviews: LocalReviewStore
    @EnvironmentObject private var saved: SavedRestaurantStore
    @EnvironmentObject private var transfer: LibraryTransfer
    @State private var allowSearch = true
    @State private var includeAverage = true
    @State private var saving = false
    @State private var recoveryKey: String?
    @State private var enteredKey = ""
    @State private var confirmsBackup = false
    @State private var confirmsRestore = false
    @State private var confirmsRecovery = false
    @State private var confirmsDelete = false
    @State private var deleteText = ""
    @State private var error: String?
    @State private var confirmsNewKey = false

    var body: some View {
        Form {
            if friends.needsLocalReset {
                Section {
                    Text("アカウントは削除済みです。端末内の記録の削除を完了してください。")
                    Button("端末内の記録の削除を完了") { completeLocalReset() }.disabled(saving)
                }
            } else if friends.isAvailable {
                privacySection
                blocksSection
                backupSection
                recoverySection
                deleteSection
            } else {
                Section {
                    Text("現在は端末内モードです。プロフィール・保存・レビューをこの端末で利用できます。友達・バックアップ・引き継ぎにはサーバーへの接続が必要です。")
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Text("meshinowa \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                Text("おいしい店は、友達が知っている。")
            }
        }
        .font(MeshinowaFont.text(15)).scrollContentBackground(.hidden).background(MeshinowaTheme.paper)
        .navigationTitle("設定").navigationBarTitleDisplayMode(.inline).reservesFloatingTabBarSpace()
        .task {
            guard friends.isAvailable else { return }
            await friends.loadSettings()
            allowSearch = friends.preferences?.allowIdSearch != 0
            includeAverage = friends.preferences?.includeInFriendAvg != 0
        }
        .onDisappear { recoveryKey = nil; enteredKey = "" }
        .confirmationDialog("バックアップを更新しますか？", isPresented: $confirmsBackup, titleVisibility: .visible) {
            Button("この端末の内容でバックアップ") { Task { await transfer.backup() } }
        } message: { Text("以前のバックアップは、この端末の最新の記録で置き換わります。") }
        .confirmationDialog("この端末の記録を復元しますか？", isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button("バックアップで置き換える", role: .destructive) { Task { await transfer.restore() } }
        } message: { Text("バックアップ以降にこの端末だけで変更した記録は置き換わります。") }
        .confirmationDialog("元のアカウントに切り替えますか？", isPresented: $confirmsRecovery, titleVisibility: .visible) {
            Button("アカウントと記録を引き継ぐ", role: .destructive) {
                let key = enteredKey; enteredKey = ""
                Task { await transfer.restore(recoveryKey: key) }
            }
        } message: { Text("今の端末のアカウントから切り替え、元の端末のバックアップで記録を置き換えます。今の記録が必要な場合は先にバックアップしてください。") }
        .confirmationDialog("引き継ぎコードを発行しますか？", isPresented: $confirmsNewKey, titleVisibility: .visible) {
            Button("発行する") {
                saving = true
                Task {
                    defer { saving = false }
                    do { recoveryKey = try await friends.makeRecoveryKey() }
                    catch { self.error = "コードを発行できませんでした。もう一度お試しください。" }
                }
            }
        } message: { Text("以前に発行したコードは無効になります。") }
        .alert("アカウントを削除", isPresented: $confirmsDelete) {
            TextField("削除 と入力", text: $deleteText)
            Button("キャンセル", role: .cancel) { deleteText = "" }
            Button("完全に削除", role: .destructive) { delete() }.disabled(deleteText != "削除")
        } message: { Text("レビュー・友達関係・バックアップと、この端末の記録を削除します。取り消せません。") }
        .alert("データの転送", isPresented: Binding(get: { transfer.message != nil }, set: { if !$0 { transfer.message = nil } })) {
            Button("閉じる", role: .cancel) { transfer.message = nil }
        } message: { Text(transfer.message ?? "") }
    }

    private var privacySection: some View {
        Section {
            Toggle("IDで見つけてもらう", isOn: $allowSearch)
            Toggle("友達の平均評価・フィードに含める", isOn: $includeAverage)
            Button(saving ? "保存中…" : "公開設定を保存") { savePreferences() }
                .disabled(saving || friends.preferences == nil)
        } header: { Text("公開設定") } footer: {
            Text("ID検索をオフにしても、すでにつながっている友達と申請中の相手には表示されます。写真・来店日は友達には公開しません。")
        }
    }

    private var blocksSection: some View {
        Section("ブロックした人") {
            if friends.blockedProfiles.isEmpty { Text("ブロックした人はいません").foregroundStyle(.secondary) }
            ForEach(friends.blockedProfiles) { person in
                HStack {
                    Text(person.displayName ?? "ブロックしたユーザー")
                    Spacer()
                    Button("解除") { Task { await friends.unblock(person.id) } }
                }
            }
            Text("ブロックは友達一覧や届いた申請のメニューから行えます。解除しても友達には戻りません。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var backupSection: some View {
        Section {
            Button("この端末の記録をバックアップ") { confirmsBackup = true }
            Button("バックアップからこの端末へ復元") { confirmsRestore = true }
            if transfer.isBusy { ProgressView("データを転送中…") }
        } header: { Text("自分専用のバックアップ") } footer: {
            Text("保存・レビュー・写真・来店日を自分だけが読めるサーバーに保存します。自動同期ではありません。別端末への移動前にバックアップしてください。復元するとこの端末の記録を置き換えます。")
        }
        .disabled(transfer.isBusy || saving)
    }

    private var recoverySection: some View {
        Section {
            Button("引き継ぎコードを発行") { confirmsNewKey = true }
            if let recoveryKey {
                Text(recoveryKey).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button("コードをコピー") {
                    UIPasteboard.general.setItems([["public.utf8-plain-text": recoveryKey]],
                                                  options: [.expirationDate: Date().addingTimeInterval(3600), .localOnly: true])
                }
            }
            SecureField("元の端末の引き継ぎコード", text: $enteredKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("コードでアカウントと記録を引き継ぐ") { confirmsRecovery = true }
                .disabled(enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).count != 64)
        } header: { Text("端末の引き継ぎ") } footer: {
            Text("コードを持つ人はあなたのアカウントとバックアップを利用できます。安全な場所に保管してください。再発行すると以前のコードは使えません。友達とのつながりも引き継がれます。")
        }.disabled(transfer.isBusy || saving)
    }

    private var deleteSection: some View {
        Section {
            Button("アカウントとこの端末の記録を削除", role: .destructive) { confirmsDelete = true }
        }.disabled(transfer.isBusy || saving)
    }

    private func savePreferences() {
        saving = true; error = nil
        Task {
            defer { saving = false }
            do { try await friends.updatePreferences(allowSearch: allowSearch, includeInAverage: includeAverage) }
            catch { self.error = "公開設定を保存できませんでした。もう一度お試しください。" }
        }
    }
    private func delete() {
        guard deleteText == "削除" else { return }
        saving = true; deleteText = ""
        Task {
            defer { saving = false }
            await friends.pauseReviewSync()
            do {
                try await friends.deleteAccount()
                try reviews.clear()
                try saved.clear()
                recoveryKey = nil
                friends.finishLocalReset()
                await friends.start(sharing: [])
            } catch {
                self.error = "削除を完了できませんでした。通信状況と端末の空き容量を確認してください。"
                friends.suspendsReviewSync = friends.needsLocalReset
            }
        }
    }

    private func completeLocalReset() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try reviews.clear()
                try saved.clear()
                friends.finishLocalReset()
                await friends.start(sharing: [])
            } catch { self.error = "端末内の記録を削除できませんでした。空き容量を確認して再試行してください。" }
        }
    }
}
