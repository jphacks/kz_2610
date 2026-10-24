import SwiftUI

enum MeshinowaFont {
    enum Weight: String {
        case medium = "Medium"
        case bold = "Bold"
        case black = "Black"
    }

    static func text(_ size: CGFloat, weight: Weight = .medium,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("ZenMaruGothic-\(weight.rawValue)", size: size, relativeTo: style)
    }

    static func number(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("RoundedMplus1c-Black", size: size, relativeTo: style)
    }

    static let wordmark = number(46, relativeTo: .largeTitle)
}
