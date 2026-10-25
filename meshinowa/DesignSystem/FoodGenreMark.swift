import SwiftUI

/// ジャンルを器の形で見せる印。形はジャンル、色は自分の記録を表す（地図のピンと同じ決まり）。
/// 形は 36×34 の座標で描いた output/wa-design/category-pins.html と同じもの。
struct FoodGenreMark: View {
    enum Tone {
        /// 記録なし。白地に緑の線。
        case plain
        /// いいね。ピンク。
        case liked
        /// レビュー済み。緑。
        case reviewed
        /// 自分の記録を数えるところ。からし色。
        case mine
        /// まだ記録がない。薄い線。
        case faint
    }

    let genre: FoodGenre
    var tone: Tone = .plain
    var size: CGFloat = 32

    private var fill: Color {
        switch tone {
        case .plain, .faint: return MeshinowaTheme.card
        case .liked: return MeshinowaTheme.like
        case .reviewed: return MeshinowaTheme.green
        case .mine: return MeshinowaTheme.accent
        }
    }
    private var isOutlined: Bool { tone == .plain || tone == .faint }
    private var line: Color { isOutlined ? MeshinowaTheme.green : .white }
    private var decoLine: Color { isOutlined ? MeshinowaTheme.green.opacity(0.4) : .white.opacity(0.55) }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 36
            context.scaleBy(x: scale, y: scale)
            let shape = GenreShapes.shape(for: genre)
            if shape.chopsticks {
                context.stroke(SVGPath.parse("M21 13 L30 1.5 M24.5 13 L33 2.5"),
                               with: .color(Color(red: 0.42, green: 0.29, blue: 0.2)),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            if shape.handle {
                let handle = SVGPath.parse("M26 12 C31.5 12 31.5 21 25.5 21")
                context.stroke(handle, with: .color(isOutlined ? MeshinowaTheme.green : fill),
                               lineWidth: isOutlined ? 4.4 : 3.4)
                if isOutlined { context.stroke(handle, with: .color(.white), lineWidth: 1.6) }
            }
            let body = SVGPath.parse(shape.body)
            context.fill(body, with: .color(fill))
            context.stroke(body, with: .color(line), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            if let deco = shape.deco {
                context.stroke(SVGPath.parse(deco), with: .color(decoLine),
                               style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
            if shape.caps {
                let cap = Color(red: 0.12, green: 0.3, blue: 0.24)
                context.fill(Path(roundedRect: CGRect(x: 10, y: 1, width: 16, height: 4), cornerRadius: 1.2), with: .color(cap))
                context.fill(Path(roundedRect: CGRect(x: 10, y: 29, width: 16, height: 4), cornerRadius: 1.2), with: .color(cap))
            }
        }
        .frame(width: size, height: size * 34 / 36)
        .opacity(tone == .faint ? 0.4 : 1)
        .accessibilityHidden(true)
    }
}

private enum GenreShapes {
    struct Shape {
        let body: String
        var deco: String? = nil
        var chopsticks = false
        var handle = false
        var caps = false
    }

    static func shape(for genre: FoodGenre) -> Shape {
        switch genre {
        case .washoku: // 蓋付きのお椀
            return Shape(body: "M4 17 H32 C32 25 26 30 18 30 C10 30 4 25 4 17Z M6 15.5 C6 9 11 6 18 6 C25 6 30 9 30 15.5Z",
                         deco: "M15 4.5 H21 M3.5 16.2 H32.5")
        case .sushi: // 寿司屋の湯呑
            return Shape(body: "M8 6 H28 L26.5 27 C26.3 29 25 30 23 30 H13 C11 30 9.7 29 9.5 27Z",
                         deco: "M8.6 11 H27.4 M9.3 21 H26.7")
        case .noodle: // 雷紋の丼と箸
            return Shape(body: "M2 13 H34 C34 23 27 30 18 30 C9 30 2 23 2 13Z",
                         deco: "M5 17 h3 v3 h3 v-3 h3 v3 h3 v-3 h3 v3 h3 v-3 h3 v3 h3", chopsticks: true)
        case .yakiniku: // 七輪
            return Shape(body: "M7 10 H29 L27.5 28 C27.4 29.3 26.5 30 25 30 H11 C9.5 30 8.6 29.3 8.5 28Z M5 7 H31 V10.5 H5Z",
                         deco: "M9 5 V8.5 M14 5 V8.5 M19 5 V8.5 M24 5 V8.5 M28 5 V8.5 M10 23 H26")
        case .izakaya: // 提灯
            return Shape(body: "M7 5 C3 9 3 25 7 29 H29 C33 25 33 9 29 5Z",
                         deco: "M5 11 H31 M4.3 17 H31.7 M5 23 H31", caps: true)
        case .yoshoku: // ふたをした洋皿
            return Shape(body: "M5 24 C5 14 11 9 18 9 C25 9 31 14 31 24Z M2 24 H34 V27 C34 28.5 33 29.5 31.5 29.5 H4.5 C3 29.5 2 28.5 2 27Z",
                         deco: "M16 7.5 H20")
        case .chuka: // 蒸籠
            return Shape(body: "M3 8 H33 V12 H3Z M5 12 H31 V29 C31 29.6 30.6 30 30 30 H6 C5.4 30 5 29.6 5 29Z",
                         deco: "M5 20.5 H31 M9 12 V29 M27 12 V29")
        case .cafe: // 取っ手付きのカップ
            return Shape(body: "M7 8 H26 V21 C26 26.5 22.5 30 16.5 30 C10.5 30 7 26.5 7 21Z", deco: "M3 31 H30", handle: true)
        case .bread: // 山型の食パン
            return Shape(body: "M7 14 C3 14 3 5.5 10 5.5 C12.5 3 23.5 3 26 5.5 C33 5.5 33 14 29 14 V30 H7Z", deco: "M11 14 H25")
        case .other: // 今のピンと同じ丸
            return Shape(body: "M31 17 C31 24.2 25.2 30 18 30 C10.8 30 5 24.2 5 17 C5 9.8 10.8 4 18 4 C25.2 4 31 9.8 31 17Z")
        }
    }
}

/// デザインの座標をそのまま使うための、SVG の path の小さな読み取り。M L H V C Z と小文字の h v だけを扱う。
enum SVGPath {
    static func parse(_ string: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var command: Character = "M"
        var numbers: [CGFloat] = []
        var token = ""

        func flushToken() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }
        func apply() {
            switch command {
            case "M", "L":
                var i = 0
                while i + 1 < numbers.count {
                    let point = CGPoint(x: numbers[i], y: numbers[i + 1])
                    if command == "M" && i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    current = point; i += 2
                }
            case "H": for x in numbers { current.x = x; path.addLine(to: current) }
            case "V": for y in numbers { current.y = y; path.addLine(to: current) }
            case "h": for dx in numbers { current.x += dx; path.addLine(to: current) }
            case "v": for dy in numbers { current.y += dy; path.addLine(to: current) }
            case "C":
                var i = 0
                while i + 5 < numbers.count {
                    let end = CGPoint(x: numbers[i + 4], y: numbers[i + 5])
                    path.addCurve(to: end, control1: CGPoint(x: numbers[i], y: numbers[i + 1]),
                                  control2: CGPoint(x: numbers[i + 2], y: numbers[i + 3]))
                    current = end; i += 6
                }
            case "Z", "z": path.closeSubpath()
            default: break
            }
            numbers = []
        }

        for character in string {
            if "MLHVCZhvz".contains(character) {
                flushToken(); apply(); command = character
            } else if character == " " || character == "," {
                flushToken()
            } else if character == "-" && !token.isEmpty {
                flushToken(); token = "-"
            } else {
                token.append(character)
            }
        }
        flushToken(); apply()
        return path
    }
}

#Preview("ジャンルの器") {
    VStack(spacing: 14) {
        ForEach([FoodGenreMark.Tone.plain, .liked, .reviewed, .mine, .faint], id: \.self) { tone in
            HStack(spacing: 10) {
                ForEach(FoodGenre.allCases) { genre in FoodGenreMark(genre: genre, tone: tone, size: 30) }
            }
        }
    }
    .padding()
}
