import MapKit
import SwiftUI

struct RestaurantPreview: View {
    let item: MKMapItem
    var onClose: () -> Void
    @State private var showsDetails = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.restaurantCategory)
                        .font(MeshinowaFont.text(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                    Text(item.name ?? "飲食店")
                        .font(MeshinowaFont.text(24, weight: .black, relativeTo: .title2))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .background(MeshinowaTheme.paper, in: Circle())
                        .overlay(Circle().strokeBorder(MeshinowaTheme.ink, lineWidth: 2))
                }
                .accessibilityLabel("お店の選択を解除")
            }

            Text("友達の評価は準備中です")
                .font(MeshinowaFont.text(14))
                .foregroundStyle(MeshinowaTheme.secondaryText)

            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) { actions }
            } else {
                HStack(spacing: 10) { actions }
            }
        }
        .foregroundStyle(MeshinowaTheme.ink)
        .padding(18)
        .paperCard(radius: 26, shadowOffset: 5)
        .sheet(isPresented: $showsDetails) {
            RestaurantInformationView(item: item)
        }
    }

    @ViewBuilder private var actions: some View {
        DirectionsButton(item: item)
        Button("詳細") { showsDetails = true }
            .buttonStyle(PaperButtonStyle(kind: .secondary))
    }
}

struct RestaurantInformationView: View {
    let item: MKMapItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.name ?? "飲食店")
                        .font(MeshinowaFont.text(28, weight: .black, relativeTo: .title))
                    Text(item.restaurantCategory)
                        .font(MeshinowaFont.text(14, weight: .bold))
                    VStack(alignment: .leading, spacing: 14) {
                        information("住所", value: item.placemark.title ?? "住所の情報がありません")
                        if let phone = item.phoneNumber, !phone.isEmpty {
                            information("電話番号", value: phone)
                        }
                        information("営業時間", value: "営業時間の情報がありません。来店前にお店へ確認してください。")
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .paperCard()
                    Text("友達の評価は準備中です")
                        .font(MeshinowaFont.text(14))
                        .foregroundStyle(MeshinowaTheme.secondaryText)
                }
                .padding(20)
            }
            .background(MeshinowaTheme.paper)
            .foregroundStyle(MeshinowaTheme.ink)
            .safeAreaInset(edge: .bottom) {
                DirectionsButton(item: item)
                    .padding(20)
                    .background(MeshinowaTheme.paper)
            }
            .navigationTitle("お店の情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func information(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(MeshinowaFont.text(12, weight: .black, relativeTo: .caption))
                .foregroundStyle(MeshinowaTheme.secondaryText)
            Text(value)
                .font(MeshinowaFont.text(14))
                .textSelection(.enabled)
        }
    }
}

struct DirectionsButton: View {
    let item: MKMapItem
    @State private var showsError = false

    var body: some View {
        Button {
            showsError = !item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
            ])
        } label: {
            Label("経路を見る", systemImage: "arrow.turn.up.right")
        }
        .buttonStyle(PaperButtonStyle())
        .accessibilityHint("Appleマップで徒歩の経路を開きます")
        .alert("Appleマップを開けませんでした", isPresented: $showsError) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("時間をおいて、もう一度お試しください。")
        }
    }
}

extension MKMapItem {
    var restaurantCategory: String {
        switch pointOfInterestCategory {
        case .cafe: return "カフェ"
        case .bakery: return "ベーカリー"
        case .brewery: return "ブルワリー"
        default: return "飲食店"
        }
    }
}
