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
            if let invite, let code = InviteQRCode(url: invite.url) {
                InviteQRCodeView(code: code)
                    .padding(12)
                    .background(MeshinowaTheme.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MeshinowaTheme.hairline))
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

}

/// 生成したQRの行列。白い外周を除き、表示側で4セル分の余白を確保する。
struct InviteQRCode {
    let modules: [[Bool]]

    init?(url: URL) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let side = Int(output.extent.width)
        guard side > 0, side <= 200 else { return nil }
        var pixels = [UInt8](repeating: 255, count: side * side)
        CIContext().render(output, toBitmap: &pixels, rowBytes: side, bounds: output.extent,
                           format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        let dark = (0..<side * side).filter { pixels[$0] < 128 }
        guard let minX = dark.map({ $0 % side }).min(), let maxX = dark.map({ $0 % side }).max(),
              let minY = dark.map({ $0 / side }).min(), let maxY = dark.map({ $0 / side }).max(),
              maxX - minX == maxY - minY else { return nil }
        modules = (minY...maxY).map { y in (minX...maxX).map { x in pixels[y * side + x] < 128 } }
    }
}

/// 案1b「緑のつぶ」。点の色とロゴは既存のテーマを使う。
struct InviteQRCodeView: View {
    let code: InviteQRCode
    var size: CGFloat = 184

    private var count: Int { code.modules.count }
    private var unit: CGFloat { size / CGFloat(count + 8) }
    private var logoModules: Int { max(3, Int((Double(count) * 0.22).rounded()) / 2 * 2 + 1) }
    private var logoSize: CGFloat { CGFloat(logoModules) * unit }

    var body: some View {
        ZStack {
            Canvas { context, _ in
                let middle = count / 2
                let halfLogo = logoModules / 2
                for y in 0..<count {
                    for x in 0..<count where code.modules[y][x] {
                        let eye = (x < 7 && y < 7) || (x >= count - 7 && y < 7) || (x < 7 && y >= count - 7)
                        let logo = abs(x - middle) <= halfLogo && abs(y - middle) <= halfLogo
                        guard !eye && !logo else { continue }
                        let circle = CGRect(x: (CGFloat(x) + 4.07) * unit, y: (CGFloat(y) + 4.07) * unit,
                                            width: 0.86 * unit, height: 0.86 * unit)
                        context.fill(Path(ellipseIn: circle), with: .color(MeshinowaTheme.mintInk))
                    }
                }
                for (x, y) in [(0, 0), (count - 7, 0), (0, count - 7)] {
                    let origin = CGPoint(x: CGFloat(x + 4) * unit, y: CGFloat(y + 4) * unit)
                    let outer = CGRect(x: origin.x + 0.5 * unit, y: origin.y + 0.5 * unit,
                                       width: 6 * unit, height: 6 * unit)
                    context.stroke(Path(roundedRect: outer, cornerRadius: 2.4 * unit),
                                   with: .color(MeshinowaTheme.mintInk), lineWidth: unit)
                    let inner = CGRect(x: origin.x + 2 * unit, y: origin.y + 2 * unit,
                                       width: 3 * unit, height: 3 * unit)
                    context.fill(Path(roundedRect: inner, cornerRadius: 1.2 * unit),
                                 with: .color(MeshinowaTheme.mintInk))
                }
            }
            Circle().fill(MeshinowaTheme.mint)
                .frame(width: logoSize - 1.2 * unit, height: logoSize - 1.2 * unit)
                .padding(0.6 * unit)
                .background(MeshinowaTheme.card, in: Circle())
                .overlay { BowlMark(size: logoSize * 0.74, holes: MeshinowaTheme.mint) }
        }
        .frame(width: size, height: size)
        .background(MeshinowaTheme.card)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("招待QRコード。iPhoneのカメラで読み取ると申請画面が開きます")
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
