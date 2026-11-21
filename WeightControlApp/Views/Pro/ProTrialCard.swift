import SwiftUI

/// ホームのいちばん上に出す、Pro の無料お試しのカード。仕様は docs/PRO.md。
///
/// - まだお試しを始めていないとき：「1 か月無料で試せます」（「あとで」で閉じられる）。
///   初回設定を終えてホームを開くと、まずこのカードが見えます。
/// - お試しの残りが 3 日以下のとき：「お試しはあと N 日です」と前もって知らせる。
/// - それ以外（お試し中で残りが多い・終わった・購入済み）は出しません。
///   終わったあとは、各カードの「Pro で見られます」から説明を開けます。
struct ProTrialCard: View {
    let status: ProAccessStatus

    @AppStorage(ProPreferenceKey.trialOfferDismissed) private var isOfferDismissed = false
    @State private var isShowingOffer = false

    /// 残りが何日以下になったら知らせるか
    static let reminderDays = 3

    /// カードを出すかどうか（ホーム側で判断するために static にしています）
    static func isVisible(status: ProAccessStatus, isOfferDismissed: Bool) -> Bool {
        switch status {
        case .trialAvailable: !isOfferDismissed
        case .trial(_, let daysLeft): daysLeft <= reminderDays
        case .trialEnded, .purchased, .debugUnlocked: false
        }
    }

    var body: some View {
        DashboardCard(title: "Pro", systemImage: "star.circle", badge: "Pro") {
            switch status {
            case .trial(_, let daysLeft):
                Text("Pro のお試しは、あと \(daysLeft) 日です。終わったあとも、記録やグラフはそのまま無料で使えます。")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Pro について") { isShowingOffer = true }
            default:
                Text("目標に届く日・見込みの幅・チートデーの提案を、1 か月無料で試せます。自動で料金がかかることはありません。")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { offerButtons }
                    VStack(alignment: .leading, spacing: 8) { offerButtons }
                }
            }
        }
        .sheet(isPresented: $isShowingOffer) {
            ProOfferView()
        }
    }

    @ViewBuilder
    private var offerButtons: some View {
        Button("くわしく見る") { isShowingOffer = true }
            .buttonStyle(.borderedProminent)
        Button("あとで") { isOfferDismissed = true }
            .buttonStyle(.bordered)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ProTrialCard(status: .trialAvailable)
            ProTrialCard(status: .trial(endsAt: .now.addingTimeInterval(2 * 86_400), daysLeft: 2))
            ProTrialCard(status: .trialAvailable)
                .dynamicTypeSize(.accessibility2)
                .preferredColorScheme(.dark)
        }
        .padding()
    }
    .environment(ProAccess())
}
