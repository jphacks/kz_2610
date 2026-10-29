import SwiftUI

/// のれんのタブに並べられる項目。enum に準拠させれば、ケースを足すだけでタブが増える。
protocol NorenTabItem: Identifiable, Hashable {
    var title: String { get }
    /// 選んだタブにだけ出す SF Symbols の名前。
    var symbol: String { get }
}

/// 既存の形に加え、地図の小さなのれんと保存の2枚のれんを選べる。
enum NorenStyle {
    case standard, rod, collection
    var shortHeight: CGFloat { self == .rod ? 28 : (self == .collection ? 34 : 32) }
    var longHeight: CGFloat { self == .rod ? 40 : (self == .collection ? 46 : 48) }
}

/// 上の板から垂れ下がるのれん風のタブ。選んだ一枚が竿から落ちるように垂れ、揺れながら止まる。
/// 項目が `fitsCount` 枚までなら横幅を等分し、それより多ければ横にスクロールする。
struct NorenTabs<Item: NorenTabItem>: View {
    let items: [Item]
    @Binding var selection: Item
    var fitsCount = 4
    var style: NorenStyle = .standard
    var counts: [Item: Int] = [:]

    /// 切り替えるたびに増やし、すべてのタブに動き出しを知らせる。
    @State private var changeID = 0
    /// 選択が右へ動いたら 1、左なら -1。揺れの向きに使う。
    @State private var travel = 1

    var body: some View {
        ZStack(alignment: .top) {
            if style != .standard {
                Capsule().fill(MeshinowaTheme.mustardInk)
                    .frame(height: 4)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(.horizontal, style == .collection ? -6 : 0)
            }
            tabs.padding(.top, style == .standard ? 0 : 3)
        }
        .onChange(of: selection) { old, new in
            travel = index(of: new) >= index(of: old) ? 1 : -1
            changeID += 1
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var tabs: some View {
        Group {
            if items.count <= fitsCount {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(items) { tab($0).frame(maxWidth: .infinity) }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 4) {
                            ForEach(items) { item in
                                tab(item).frame(width: style == .rod ? (selection == item ? 60 : 52) : 84).id(item.id)
                            }
                        }
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .white, location: 0),
                                               .init(color: .white, location: style == .rod ? 0.86 : 1),
                                               .init(color: style == .rod ? .clear : .white, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .onChange(of: selection) { _, item in
                        withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(item.id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func tab(_ item: Item) -> some View {
        NorenTab(item: item,
                 isOn: selection == item,
                 offset: index(of: item) - index(of: selection),
                 travel: travel,
                 changeID: changeID, style: style, count: counts[item]) { selection = item }
    }

    private func index(of item: Item) -> Int {
        items.firstIndex(of: item) ?? 0
    }
}

/// のれん一枚。白い短い布がいつも掛かっていて、選ぶと緑の長い布が上から垂れてくる。
private struct NorenTab<Item: NorenTabItem>: View {
    let item: Item
    let isOn: Bool
    /// 選ばれたタブから何枚離れているか。隣ほど風を受けて大きく揺れる。
    let offset: Int
    let travel: Int
    let changeID: Int
    let style: NorenStyle
    let count: Int?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion: NorenMotion?
    @State private var isAnimating = false
    @State private var lastOn = false

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(paused: !isAnimating)) { context in
                cloth(motion?.pose(at: context.date) ?? .resting(isOn))
            }
            .frame(height: style.longHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(NorenPressStyle())
        .accessibilityLabel(item.title)
        .accessibilityValue(count.map { "\($0)件" } ?? "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .onAppear { lastOn = isOn }
        .onChange(of: changeID) { _, _ in
            let kind: NorenMotion.Kind
            if isOn {
                kind = .drop
            } else if lastOn {
                kind = .retract
            } else {
                kind = .flutter(distance: offset)
            }
            lastOn = isOn
            motion = NorenMotion(kind: kind, start: .now, travel: CGFloat(travel), reduceMotion: reduceMotion)
            isAnimating = true
        }
        // 動きが収まったら TimelineView を止め、静止した形で描き直す。
        .task(id: motion?.start) {
            guard let duration = motion?.duration else { return }
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled { isAnimating = false }
        }
    }

    private func cloth(_ pose: NorenPose) -> some View {
        ZStack(alignment: .top) {
            // いつも掛かっている白い短い布。
            titleLabel(selected: false)
                .font(style == .standard ? MeshinowaFont.text(13) : MeshinowaFont.wa(style == .collection ? 15 : 13, bold: false))
                .foregroundStyle(MeshinowaTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .offset(x: pose.baseSway * 0.5)
                .opacity(1 - pose.reveal)
                .frame(maxWidth: .infinity)
                .frame(height: style.shortHeight)
                .background {
                    NorenCloth(sway: pose.baseSway)
                        .fill(MeshinowaTheme.card)
                        .shadow(color: .black.opacity(0.14), radius: 4, y: 1)
                }

            // 選んだときに垂れてくる緑の長い布。中身も布と一緒に下りてきて、布の形で切り抜く。
            if pose.length > 0 {
                let shape = NorenCloth(length: pose.length, sway: pose.sway, slitDepth: pose.slit)
                Group {
                    if style == .standard {
                        VStack(spacing: 2) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .scaleEffect(0.6 + 0.4 * pose.reveal)
                            Text(item.title).font(MeshinowaFont.text(13, weight: .bold))
                        }
                    } else {
                        titleLabel(selected: true)
                            .font(MeshinowaFont.wa(style == .collection ? 15 : 13))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.bottom, style == .standard ? 6 : 4)
                .opacity(pose.reveal)
                .offset(x: pose.sway * 0.55, y: -(1 - min(pose.length, 1)) * 14)
                .frame(maxWidth: .infinity)
                .frame(height: style.longHeight)
                .mask { shape }
                .background {
                    shape.fill(MeshinowaTheme.green)
                        .shadow(color: .black.opacity(0.2 * min(pose.length, 1)), radius: 5, y: 2)
                }
                .opacity(pose.opacity)
            }
        }
    }

    private func titleLabel(selected: Bool) -> some View {
        HStack(spacing: 6) {
            if style == .collection {
                Image(systemName: selected ? item.symbol + ".fill" : item.symbol)
                    .foregroundStyle(selected ? MeshinowaTheme.paper : (item.symbol == "heart" ? MeshinowaTheme.like : MeshinowaTheme.green))
            }
            Text(item.title)
            if let count {
                Text("\(count)").font(MeshinowaFont.number(14, relativeTo: .caption))
            }
        }
    }

}

/// 押しているあいだ、布を指で軽く引いたように少し下げる。薄くはしない。
private struct NorenPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(duration: 0.18, bounce: 0.5), value: configuration.isPressed)
    }
}

/// ある瞬間ののれんの形。
private struct NorenPose {
    static let shortHeight: CGFloat = 32
    static let longHeight: CGFloat = 48
    static let fullSlit: CGFloat = 9

    /// 緑の布がどこまで垂れたか。1 で下まで。ばねで少し行き過ぎることもある。
    var length: CGFloat
    /// 緑の布の裾が横に振れる量（pt）。
    var sway: CGFloat
    var slit: CGFloat
    /// 緑の布の文字の出方。
    var reveal: CGFloat
    /// 白い布の裾の揺れ。隣ののれんが落ちた風を受ける。
    var baseSway: CGFloat = 0
    var opacity: CGFloat = 1

    static func resting(_ isOn: Bool) -> NorenPose {
        NorenPose(length: isOn ? 1 : 0, sway: 0, slit: isOn ? fullSlit : 0, reveal: isOn ? 1 : 0)
    }
}

/// 一回の切り替えでのれんが描く動き。時刻を渡すとその瞬間の形を返す。
private struct NorenMotion {
    enum Kind {
        /// 竿から落ちて、ばねのように伸び縮みし、揺れながら止まる。
        case drop
        /// 前に選ばれていた布を、くるっと巻き上げる。
        case retract
        /// 隣ののれんが落ちた風で、白い布がそよぐ。
        case flutter(distance: Int)
    }

    let kind: Kind
    let start: Date
    let travel: CGFloat
    let reduceMotion: Bool

    /// 巻き上げが少し進んでから落とし始め、二枚の動きが重なりすぎないようにする。
    private static let dropDelay = 0.07
    private static let retractDuration = 0.22

    var duration: Double {
        if reduceMotion { return 0.25 }
        switch kind {
        case .drop: return Self.dropDelay + 1.7
        case .retract: return Self.retractDuration
        case .flutter(let distance): return flutterDelay(distance) + 1.3
        }
    }

    func pose(at date: Date) -> NorenPose {
        let t = date.timeIntervalSince(start)
        if reduceMotion { return fadedPose(t) }
        switch kind {
        case .drop: return dropPose(t - Self.dropDelay)
        case .retract: return retractPose(t)
        case .flutter(let distance): return flutterPose(t - flutterDelay(distance), distance: distance)
        }
    }

    private func dropPose(_ t: Double) -> NorenPose {
        guard t > 0 else { return NorenPose(length: 0, sway: 0, slit: 0, reveal: 0) }
        guard t < 1.7 else { return .resting(true) }
        // 減衰振動するばね。布が落ちて少し伸び、戻って止まる。
        let omega = 2 * Double.pi / 0.52, zeta = 0.56
        let root = (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * t)
        let length = 1 - decay * (cos(omega * root * t) + zeta / root * sin(omega * root * t))
        // 竿が動いた向きと逆に裾が遅れ、振り子のように揺れて収まる。
        let swing = -travel * 9 * exp(-t / 0.36) * sin(2 * Double.pi * t / 0.6)
        let slit = NorenPose.fullSlit * smoothstep((t - 0.14) / 0.32)
        let reveal = clamp((length - 0.35) / 0.5)
        return NorenPose(length: length, sway: swing * min(length, 1), slit: slit, reveal: reveal)
    }

    private func retractPose(_ t: Double) -> NorenPose {
        let p = clamp(t / Self.retractDuration)
        guard p < 1 else { return .resting(false) }
        let eased = p * p * (3 - 2 * p)
        return NorenPose(length: 1 - eased,
                         sway: travel * 3.5 * sin(Double.pi * p),
                         slit: NorenPose.fullSlit * (1 - eased),
                         reveal: 1 - clamp(p * 2.5))
    }

    private func flutterPose(_ t: Double, distance: Int) -> NorenPose {
        guard t > 0, t < 1.3, distance != 0 else { return .resting(false) }
        // 選ばれたのれんから遠ざかる向きにあおられる。
        let away = distance > 0 ? 1.0 : -1.0
        let amplitude = 3.2 / Double(abs(distance))
        let sway = away * amplitude * exp(-t / 0.3) * sin(2 * Double.pi * t / 0.5)
        var pose = NorenPose.resting(false)
        pose.baseSway = sway
        return pose
    }

    /// 視差効果を減らす設定のときは、揺らさずに色だけ入れ替える。
    private func fadedPose(_ t: Double) -> NorenPose {
        let p = clamp(t / 0.25)
        switch kind {
        case .drop:
            var pose = NorenPose.resting(true)
            pose.opacity = p
            return pose
        case .retract:
            var pose = NorenPose.resting(true)
            pose.opacity = 1 - p
            return p < 1 ? pose : .resting(false)
        case .flutter:
            return .resting(false)
        }
    }

    private func flutterDelay(_ distance: Int) -> Double {
        // 風は隣から順に届く。
        Self.dropDelay + 0.05 * Double(abs(distance))
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    private func smoothstep(_ x: Double) -> Double {
        let p = clamp(x)
        return p * p * (3 - 2 * p)
    }
}

/// のれん一枚の形。上は竿に付いて動かず、裾だけが `sway` だけ横に振れて布がしなる。
/// `length` で上からどこまで垂れたかを決め、裾の真ん中に切れ目を入れる。
struct NorenCloth: Shape {
    var length: CGFloat = 1
    var sway: CGFloat = 0
    var slitDepth: CGFloat = 0
    var slitWidth: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let top = rect.minY
        let bottom = top + rect.height * length
        let height = bottom - top
        guard height > 1 else { return Path() }
        let topRadius = min(3, height / 2)
        let radius = min(9, max(0, (height - topRadius) / 2))
        // 上は真下に垂れ、裾に近いほど振れる。布がしなって見えるよう、制御点を半分より下に置く。
        let bend = top + height * 0.55
        let left = rect.minX, right = rect.maxX
        let slit = min(slitDepth, height - radius)
        let half = slitWidth / 2, mid = rect.midX + sway

        var path = Path()
        path.move(to: CGPoint(x: left + topRadius, y: top))
        path.addLine(to: CGPoint(x: right - topRadius, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + topRadius), control: CGPoint(x: right, y: top))
        path.addQuadCurve(to: CGPoint(x: right + sway, y: bottom - radius), control: CGPoint(x: right, y: bend))
        path.addQuadCurve(to: CGPoint(x: right + sway - radius, y: bottom), control: CGPoint(x: right + sway, y: bottom))
        if slit > 0 {
            path.addLine(to: CGPoint(x: mid + half, y: bottom))
            // 切れ目の奥は布の上側に近いので、裾ほどは振れない。
            path.addLine(to: CGPoint(x: mid - sway * 0.2, y: bottom - slit))
            path.addLine(to: CGPoint(x: mid - half, y: bottom))
        }
        path.addLine(to: CGPoint(x: left + sway + radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left + sway, y: bottom - radius), control: CGPoint(x: left + sway, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: top + topRadius), control: CGPoint(x: left, y: bend))
        path.addQuadCurve(to: CGPoint(x: left + topRadius, y: top), control: CGPoint(x: left, y: top))
        path.closeSubpath()
        return path
    }
}

#Preview("のれん") {
    struct Demo: View {
        @State private var genre: RestaurantGenre = .all
        var body: some View {
            NorenTabs(items: RestaurantGenre.allCases, selection: $genre)
                .padding(12)
                .background(MeshinowaTheme.ground)
        }
    }
    return Demo()
}
