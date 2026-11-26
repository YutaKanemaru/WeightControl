import SwiftUI

/// Pro の中身を「ぼかして」見せ、上に「Pro で見られます」のボタンを重ねる部品。仕様は docs/PRO.md。
///
/// お試しが終わったあとも、カードや項目は残したまま中身だけを隠すのに使います。
///
/// ## 本当の値を渡さないこと
/// ぼかしは見た目だけなので、`placeholder` には **本当の値ではなく、決まった見本の値** を渡します
/// （本当の日付をぼかすと、目をこらしたりスクリーンショットを加工したりで読めてしまうため）。
/// VoiceOver（画面の読み上げ）でも見本は読まず、「Pro で見られます」だけを読み上げます。
///
/// 使いかた:
/// ```swift
/// ProLockedContent("目標に届く日は Pro で見られます") {
///     MetricView("このペースなら", text: Text("2027年3月8日"), unit: "ごろ")
/// }
/// ```
struct ProLockedContent<Placeholder: View>: View {
    private let message: LocalizedStringKey
    private let placeholder: Placeholder

    @State private var isShowingOffer = false

    init(_ message: LocalizedStringKey = "Pro で見られます", @ViewBuilder placeholder: () -> Placeholder) {
        self.message = message
        self.placeholder = placeholder()
    }

    var body: some View {
        placeholder
            .blur(radius: 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                Button {
                    isShowingOffer = true
                } label: {
                    Label(message, systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Pro の説明を開きます")
            }
            .sheet(isPresented: $isShowingOffer) {
                ProOfferView()
            }
    }
}

/// 「🔒 〜は Pro で見られます」の小さな 1 行。押すと Pro の説明を開く。
/// グラフの点線の予測のように、ぼかす中身がないものに使います。
struct ProLockedHint: View {
    private let message: LocalizedStringKey
    @State private var isShowingOffer = false

    init(_ message: LocalizedStringKey) {
        self.message = message
    }

    var body: some View {
        Button {
            isShowingOffer = true
        } label: {
            Label(message, systemImage: "lock.fill")
                .font(.footnote)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Pro の説明を開きます")
        .sheet(isPresented: $isShowingOffer) {
            ProOfferView()
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        DashboardCard(title: "達成の見込み", systemImage: "flag.checkered") {
            ProLockedContent("目標に届く日は Pro で見られます") {
                MetricView("このペースなら", text: Text("2027年3月8日"), unit: "ごろ", caption: Text("目標体重に届く見込みです"))
            }
        }
        DashboardCard(title: "達成の見込み", systemImage: "flag.checkered") {
            ProLockedContent("目標に届く日は Pro で見られます") {
                MetricView("このペースなら", text: Text("2027年3月8日"), unit: "ごろ")
            }
        }
        .dynamicTypeSize(.accessibility2)
        .preferredColorScheme(.dark)
    }
    .padding()
    .environment(ProAccess.previewTrialEnded())
}
