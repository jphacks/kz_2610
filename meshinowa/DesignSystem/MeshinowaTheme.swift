import SwiftUI

/// 白地に写真とカードを並べる v3 デザインの共通色。
enum MeshinowaTheme {
    // 面
    static let paper = Color.white
    static let card = Color.white
    static let field = hex(0xF4F5F2)
    static let hairline = hex(0xE3E5E2)
    static let outline = hex(0xD5D8D4)
    static let photo = hex(0xEADFCB)

    // 文字
    static let ink = hex(0x1C1F1D)
    static let bodyText = hex(0x4F5550)
    static let secondaryText = hex(0x6B716D)

    // ブランド
    static let green = hex(0x27755B)
    static let mint = hex(0xDDF0E4)
    static let mintInk = hex(0x1F6B4F)
    /// 自分の評価だけに使う。
    static let accent = hex(0xE8AD45)
    static let mustardSoft = hex(0xFBEBC8)
    static let mustardInk = hex(0x7A5410)
    /// 「いいね」だけに使うピンク。
    static let like = hex(0xE5577E)
    static let likeSoft = hex(0xFCE4EB)
    static let likeInk = hex(0xA3254B)

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}
