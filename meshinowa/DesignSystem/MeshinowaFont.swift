import SwiftUI

enum MeshinowaFont {
    enum Weight {
        case medium
        case bold
        /// 見出し。丸ゴシックの太字になる。
        case black
    }

    static func text(_ size: CGFloat, weight: Weight = .medium,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        switch weight {
        case .medium: return .custom("HiraginoSans-W3", size: size, relativeTo: style)
        case .bold: return .custom("HiraginoSans-W6", size: size, relativeTo: style)
        case .black: return heading(size, relativeTo: style)
        }
    }

    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom("RoundedMplus1c-ExtraBold", size: size, relativeTo: style)
    }

    static func number(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("RoundedMplus1c-ExtraBold", size: size, relativeTo: style)
    }

    /// 地図と保存の見出し・のれんに使う丸い和文書体。
    static func wa(_ size: CGFloat, bold: Bool = true, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom(bold ? "ZenMaruGothic-Bold" : "ZenMaruGothic-Medium", size: size, relativeTo: style)
    }

    static let wordmark = number(46, relativeTo: .largeTitle)
}
