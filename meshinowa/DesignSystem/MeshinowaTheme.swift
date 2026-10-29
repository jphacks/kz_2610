import SwiftUI

/// 白地に写真とカードを並べる v3 デザインの共通色。
enum MeshinowaTheme {
    // 面
    static let ground = hex(0xFDF8EE)
    static let paper = Color.white
    static let card = Color.white
    static let field = hex(0xF4F5F2)
    static let hairline = hex(0xE3E5E2)
    static let outline = hex(0xD5D8D4)
    static let photo = hex(0xEADFCB)

    // 文字
    static let ink = hex(0x1C1F1D)
    static let rod = hex(0x3B3530)
    static let bodyText = hex(0x4F5550)
    static let secondaryText = hex(0x6B716D)

    // ブランド
    static let green = hex(0x27755B)
    static let mint = hex(0xDDF0E4)
    static let mintInk = hex(0x1F6B4F)
    /// 緑の上に置くロゴの輪。
    static let cream = hex(0xFDF8EE)
    /// タブバーで選んだタブの後ろにともる、提灯の灯り。
    static let lanternLight = hex(0xFBEBC8)
    static let lanternGlow = hex(0xF2B65A)
    /// 自分の評価だけに使う。
    static let accent = hex(0xE8AD45)
    static let mustardSoft = hex(0xFBEBC8)
    static let mustardInk = hex(0x7A5410)
    /// 「いいね」だけに使うピンク。
    static let like = hex(0xE5577E)
    static let likeSoft = hex(0xFCE4EB)
    static let danger = hex(0xD93A3A)
    static let likeInk = hex(0xA3254B)

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// Google マップの地図色。施設名は隠し、駅名や道路番号は残す。
enum MeshinowaMapStyle {
    static let json = #"""
    [
      {"elementType":"geometry","stylers":[{"color":"#F1EADB"}]},
      {"elementType":"labels.text.fill","stylers":[{"color":"#6B716D"}]},
      {"elementType":"labels.text.stroke","stylers":[{"color":"#FDF8EE"}]},
      {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#EAE2D0"}]},
      {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
      {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#DDE6D3"}]},
      {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#FFFFFF"}]},
      {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#DCD2BE"}]},
      {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#FFFFFF"}]},
      {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#FFFFFF"}]},
      {"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#B9C8C4"}]},
      {"featureType":"transit.station","elementType":"labels.icon","stylers":[{"visibility":"on"}]},
      {"featureType":"transit.station","elementType":"labels.text","stylers":[{"visibility":"on"}]},
      {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#3B5F86"}]},
      {"featureType":"road.highway","elementType":"labels","stylers":[{"visibility":"off"}]},
      {"featureType":"road.highway.controlled_access","elementType":"labels","stylers":[{"visibility":"off"}]},
      {"featureType":"water","elementType":"geometry","stylers":[{"color":"#C9DCE3"}]}
    ]
    """#
}
