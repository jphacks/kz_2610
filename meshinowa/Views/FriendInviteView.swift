import SwiftUI
import CoreImage.CIFilterBuiltins

struct FriendInviteCard: View {
    @EnvironmentObject private var store: FriendStore
    @State private var invite: FriendInvite?
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false
    @State private var confirmsRotation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("友達を招待する").font(MeshinowaFont.heading(20))
            if busy { ProgressView("招待を用意しています…") }
            if let invite, let image = qrImage(invite.url) {
                Image(uiImage: image).interpolation(.none).resizable()
                    .frame(width: 184, height: 184).padding(12)
                    .background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("招待QRコード。iPhoneのカメラで読み取ると申請画面が開きます")
                Text("iPhoneのカメラで読み取るか、リンクを送って招待できます。")
                    .font(MeshinowaFont.text(13)).foregroundStyle(MeshinowaTheme.bodyText)
                ShareLink(item: "メシノワで友達になろう！\n\(invite.url.absoluteString)") {
                    Label("招待リンクを送る", systemImage: "square.and.arrow.up")
                }.buttonStyle(PaperButtonStyle())
                HStack {
                    Button(copied ? "コピーしました" : "リンクをコピー") {
                        UIPasteboard.general.string = invite.url.absoluteString
                        copied = true
                    }
                    Spacer()
                    Button("新しいリンク") { confirmsRotation = true }
                }.font(MeshinowaFont.text(13, weight: .bold))
            }
            if let error {
                Text(error).font(MeshinowaFont.text(13)).foregroundStyle(MeshinowaTheme.bodyText)
                Button("もう一度試す") { Task { await load() } }.disabled(busy)
            }
            Text("リンクを開いただけでは友達になりません。相手が申請し、あなたが承認するとつながります。")
                .font(MeshinowaFont.text(12)).foregroundStyle(MeshinowaTheme.secondaryText)
        }
        .padding(18)
        .background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MeshinowaTheme.hairline))
        .disabled(busy)
        .task(id: store.me?.id) { if store.me != nil { invite = nil; await load() } }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
        .confirmationDialog("新しいリンクを作りますか？", isPresented: $confirmsRotation, titleVisibility: .visible) {
            Button("作る") { Task { await load(rotate: true) } }
        } message: { Text("今のリンクとQRコードは使えなくなります。") }
    }

    private func load(rotate: Bool = false) async {
        busy = true; error = nil; copied = false
        let identity = store.me?.id
        defer { busy = false }
        do {
            let result = try await store.makeInvite(rotate: rotate)
            guard !Task.isCancelled, store.me?.id == identity else { return }
            invite = result
        } catch { self.error = "招待リンクを用意できませんでした。IDでの追加も使えます。" }
    }

    private func qrImage(_ url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output.transformed(by: .init(scaleX: 8, y: 8)),
                                                    from: output.extent.applying(.init(scaleX: 8, y: 8))) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct FriendInviteLanding: View {
    let token: String
    @EnvironmentObject private var store: FriendStore
    @Environment(\.dismiss) private var dismiss
    @State private var result: FriendInviteResult?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if !store.isAvailable {
                        Text("友達の機能につながっていません").font(MeshinowaFont.heading(20))
                        Text("接続先を設定したアプリで、もう一度招待を開いてください。")
                    } else {
                        if busy { ProgressView("招待を確認しています…") }
                        if let result {
                            if let profile = result.profile {
                                FriendAvatar(name: profile.displayName, size: 72, symbol: profile.avatarSymbol)
                                Text(profile.displayName).font(MeshinowaFont.heading(25))
                                Text("@\(profile.handle)").foregroundStyle(MeshinowaTheme.bodyText)
                            }
                            Text(message(result.state)).multilineTextAlignment(.center)
                            if result.state == "ok" {
                                Text("申請し、相手が承認すると友達になります。お互いの評価が地図に表示されます。")
                                    .font(MeshinowaFont.text(14)).foregroundStyle(MeshinowaTheme.bodyText)
                                Button("友達申請を送る") { Task { await load(send: true) } }
                                    .buttonStyle(PaperButtonStyle()).disabled(busy)
                            } else if result.state == "pending_received", let id = result.requestId {
                                Button("承認する") { Task { await accept(id) } }
                                    .buttonStyle(PaperButtonStyle()).disabled(busy)
                            } else if result.state == "friend", let profile = result.profile {
                                NavigationLink("\(profile.displayName)さんの評価を地図で見る") {
                                    FriendMapScreen(friendID: profile.id)
                                }.buttonStyle(PaperButtonStyle())
                            }
                        }
                        if let error {
                            Text(error).foregroundStyle(MeshinowaTheme.bodyText)
                            Button("もう一度確認する") { Task { await load() } }.disabled(busy)
                        }
                    }
                    Button("閉じる") { dismiss() }.buttonStyle(PaperButtonStyle(kind: .secondary))
                }.padding(24)
            }
            .font(MeshinowaFont.text(16)).foregroundStyle(MeshinowaTheme.ink)
            .background(MeshinowaTheme.ground)
            .navigationTitle("友達への招待").navigationBarTitleDisplayMode(.inline)
            .task(id: token) { if store.isAvailable { await load() } }
        }.tint(MeshinowaTheme.green)
    }

    private func message(_ state: String) -> String {
        switch state {
        case "ok": return "メシノワへの招待が届いています"
        case "self": return "これはあなたの招待です。友達にリンクを送ってください。"
        case "pending_sent": return "申請中です。相手の承認をお待ちください。"
        case "pending_received": return "この人から友達申請が届いています。"
        case "friend": return "すでに友達です。"
        default: return "この招待は使えません。送ってくれた人に、もう一度送ってもらってください。"
        }
    }
    private func load(send: Bool = false) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let value = try await store.inviteResult(token: token, send: send)
            guard !Task.isCancelled else { return }
            result = value
            if send { await store.refresh() }
        } catch { self.error = "招待を確認できませんでした。通信状態を確認してお試しください。" }
    }
    private func accept(_ id: String) async {
        busy = true; error = nil
        defer { busy = false }
        do { try await store.acceptInviteRequest(id: id); await load() }
        catch { self.error = "承認できませんでした。もう一度招待を確認してください。" }
    }
}
