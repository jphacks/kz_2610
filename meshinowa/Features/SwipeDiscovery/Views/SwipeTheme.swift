import SwiftUI
import UIKit

/// お店スワイプの色と文字。既存の共通色（MeshinowaTheme）・文字（MeshinowaFont）は読むだけで変更しない。
/// 矢印・ボタン・オーバーレイが同じ色になるよう、行きたい色・イマイチ色はここだけで定義する。
enum SwipeTheme {
    // MARK: 面
    /// 和モダンな生成り色の背景。
    static let background = dynamic(light: 0xF4EFE6, dark: 0x171A18)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x242826)
    static let field = dynamic(light: 0xF4F5F2, dark: 0x2E3230)
    static let hairline = dynamic(light: 0xE3E5E2, dark: 0x3A3F3C)
    static let mapPlaceholder = dynamic(light: 0xE7EDE4, dark: 0x2B3330)

    // MARK: 文字
    static let ink = dynamic(light: 0x1C1F1D, dark: 0xF1F2EF)
    static let bodyText = dynamic(light: 0x4F5550, dark: 0xC9CDC8)
    static let secondaryText = dynamic(light: 0x6B716D, dark: 0xA3A9A4)

    // MARK: ブランド
    static let brand = MeshinowaTheme.green
    static let star = MeshinowaTheme.accent

    // MARK: 判断の色（灰色＝イマイチ、ピンク＝行きたい）。明るさにも差を付ける。
    static let interested = dynamic(light: 0xE5577E, dark: 0xF07A9A)
    static let notInterested = dynamic(light: 0x6E7681, dark: 0x9AA3AE)
    static let undo = dynamic(light: 0x4F5550, dark: 0xC9CDC8)

    // MARK: カテゴリータグ（category-pins.html の .tag と同じ配色）
    static let tagBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? uiColor(0x1F6B4F).withAlphaComponent(0.35) : uiColor(0xDDF0E4)
    })
    static let tagText = dynamic(light: 0x1F6B4F, dark: 0xCDEBD8)
    static let tagOutline = Color(uiColor: UIColor { trait in
        (trait.userInterfaceStyle == .dark ? uiColor(0xCDEBD8) : uiColor(0x1F6B4F)).withAlphaComponent(0.4)
    })
    static let dishOutline = dynamic(light: 0xD5D8D4, dark: 0x4A504C)

    // MARK: 文字
    static func text(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        MeshinowaFont.text(size, weight: bold ? .bold : .medium, relativeTo: style)
    }

    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        MeshinowaFont.heading(size, relativeTo: style)
    }

    static func number(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        MeshinowaFont.number(size, relativeTo: style)
    }

    // MARK: カテゴリーごとの落ち着いた単色（星評価ビュー・写真の読み込み中）
    static func heroBackground(for category: SwipeCategory) -> Color {
        switch category {
        case .washoku: return dynamic(light: 0xE9DCC6, dark: 0x3A3328)
        case .sushi: return dynamic(light: 0xD9E6E8, dark: 0x27363A)
        case .noodle: return dynamic(light: 0xF0E2C4, dark: 0x3D3424)
        case .yakiniku: return dynamic(light: 0xEAD5CC, dark: 0x3D2B26)
        case .izakaya: return dynamic(light: 0xEFD9C2, dark: 0x3E3022)
        case .yoshoku: return dynamic(light: 0xEADFCB, dark: 0x3A3329)
        case .chuka: return dynamic(light: 0xEED8CF, dark: 0x3E2C27)
        case .cafe: return dynamic(light: 0xE6DCD2, dark: 0x352F2A)
        case .pan: return dynamic(light: 0xF0E3CB, dark: 0x3C3427)
        case .other: return dynamic(light: 0xE4E8E1, dark: 0x2D322E)
        }
    }

    static func symbol(for category: SwipeCategory) -> String {
        switch category {
        case .cafe: return "cup.and.saucer.fill"
        case .pan: return "birthday.cake.fill"
        case .izakaya: return "mug.fill"
        case .noodle: return "takeoutbag.and.cup.and.straw.fill"
        default: return "fork.knife"
        }
    }

    // MARK: -
    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) })
    }
}

/// 友達の頭文字アイコン（アイコン画像がない時）。
struct SwipeFriendAvatar: View {
    let name: String
    var size: CGFloat = 26

    private static let tones: [Color] = [
        Color(red: 0.95, green: 0.79, blue: 0.66), Color(red: 0.75, green: 0.85, blue: 0.93),
        Color(red: 0.91, green: 0.84, blue: 0.60), Color(red: 0.91, green: 0.76, blue: 0.82),
        Color(red: 0.80, green: 0.88, blue: 0.78), Color(red: 0.86, green: 0.82, blue: 0.93)
    ]

    var body: some View {
        let index = name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.tones.count
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(Color(red: 0.11, green: 0.12, blue: 0.11))
            .frame(width: size, height: size)
            .background(Self.tones[index], in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// 星と数値（★4.3）。
struct SwipeStarRating: View {
    let rating: Double
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.85, weight: .bold))
                .foregroundStyle(SwipeTheme.star)
            Text(rating, format: .number.precision(.fractionLength(1)))
                .font(SwipeTheme.number(size, relativeTo: .body))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("星\(rating.formatted(.number.precision(.fractionLength(1))))")
    }
}
