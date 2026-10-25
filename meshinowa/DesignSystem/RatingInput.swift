import MapKit
import SwiftUI

/// 大きな星で自分の評価を付ける。同じ星をもう一度押すと0.5点下がる。
struct BigStarRating: View {
    @Binding var rating: Double
    var starSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        rating = rating == Double(value) ? Double(value) - 0.5 : Double(value)
                    } label: {
                        Image(systemName: rating >= Double(value) ? "star.fill"
                              : (rating >= Double(value) - 0.5 ? "star.leadinghalf.filled" : "star"))
                            .font(.system(size: starSize))
                            .foregroundStyle(MeshinowaTheme.accent)
                            .frame(minWidth: 48, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }
            }
            .sensoryFeedback(.selection, trigger: rating)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if rating > 0 {
                    Text("あなたの評価")
                        .font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
                    Text(rating, format: .number.precision(.fractionLength(1)))
                        .font(MeshinowaFont.number(30, relativeTo: .title))
                } else {
                    Text("星を選んでください")
                        .font(MeshinowaFont.text(14, weight: .bold))
                }
            }
            .foregroundStyle(rating > 0 ? MeshinowaTheme.mustardInk : MeshinowaTheme.secondaryText)
            .frame(minHeight: 38)
            Text("同じ星をもう一度押すと0.5下がります")
                .font(MeshinowaFont.text(11, relativeTo: .caption2))
                .foregroundStyle(MeshinowaTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("自分の評価")
        .accessibilityValue(rating > 0 ? "\(rating.formatted(.number.precision(.fractionLength(1))))点" : "未選択")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, max(1, rating + 0.5))
            case .decrement: rating = max(1, rating - 0.5)
            @unknown default: break
            }
        }
    }
}

/// 評価するお店の見出し。ジャンルの器・店名・場所。
struct ReviewShopHeader: View {
    let item: MKMapItem

    var body: some View {
        HStack(spacing: 12) {
            FoodGenreMark(genre: item.foodGenre, size: 34)
                .frame(width: 54, height: 54)
                .background(MeshinowaTheme.photo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "飲食店")
                    .font(MeshinowaFont.heading(19, relativeTo: .title3))
                    .lineLimit(2)
                Text(subtitle)
                    .font(MeshinowaFont.text(13, relativeTo: .caption))
                    .foregroundStyle(MeshinowaTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let address = item.placemark.title?.withoutPostalCode ?? ""
        return [item.restaurantCategory, address].filter { !$0.isEmpty }.joined(separator: "・")
    }
}

/// 記録したときに押す判子。点数入りで、自分の評価のからし色。
struct RatingSeal: View {
    let rating: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(rating, format: .number.precision(.fractionLength(1)))
                .font(MeshinowaFont.number(46, relativeTo: .largeTitle))
            Text("記録")
                .font(MeshinowaFont.heading(15))
                .tracking(4)
        }
        .foregroundStyle(MeshinowaTheme.mustardInk)
        .frame(width: 128, height: 128)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 1, green: 0.99, blue: 0.96)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MeshinowaTheme.accent, lineWidth: 5))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MeshinowaTheme.accent.opacity(0.35), lineWidth: 2)
            .padding(9))
        .rotationEffect(.degrees(-6))
        .accessibilityHidden(true)
    }
}

extension View {
    /// 記録が済んだ瞬間に、判子をぽんと押して触覚で返す。終わったら onFinished を呼ぶ。
    func ratingSealOnSave(rating: Double, isPresented: Binding<Bool>, onFinished: @escaping () -> Void) -> some View {
        modifier(RatingSealModifier(rating: rating, isPresented: isPresented, onFinished: onFinished))
    }
}

private struct RatingSealModifier: ViewModifier {
    let rating: Double
    @Binding var isPresented: Bool
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Color.white.opacity(0.55).ignoresSafeArea()
                        RatingSeal(rating: rating)
                            .scaleEffect(pressed || reduceMotion ? 1 : 1.8)
                            .opacity(pressed ? 1 : 0)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(true)
                }
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: pressed) { _, new in new }
            .onChange(of: isPresented) { _, shown in
                guard shown else { pressed = false; return }
                AccessibilityNotification.Announcement("記録しました").post()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pressed = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(750))
                    onFinished()
                }
            }
    }
}
