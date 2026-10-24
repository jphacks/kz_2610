import SwiftUI

struct RestaurantGenrePicker: View {
    @Binding var selection: RestaurantGenre

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RestaurantGenre.allCases) { genre in
                    let isSelected = selection == genre
                    Button { selection = genre } label: {
                        HStack(spacing: 4) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                            Text(genre.title)
                        }
                        .font(MeshinowaFont.text(13, weight: .bold, relativeTo: .subheadline))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .foregroundStyle(isSelected ? MeshinowaTheme.card : MeshinowaTheme.ink)
                        .background(isSelected ? MeshinowaTheme.ink : MeshinowaTheme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(MeshinowaTheme.ink, lineWidth: 1.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ジャンル、\(genre.title)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
