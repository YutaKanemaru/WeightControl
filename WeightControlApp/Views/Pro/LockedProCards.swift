import SwiftUI

/// お試しが終わったあと（Pro を使えないとき）に、Pro のカードの代わりに出す「ぼかしたカード」。仕様は docs/PRO.md。
///
/// 見出しは本物のカードと同じにして「どんな機能か」は分かるようにし、中身は決まった見本の値をぼかします。
/// 本当の計算結果は渡しません（ぼかしても読めてしまうことがあるため）。

/// 「見込みの幅」カードのぼかし版（本物は `ForecastRangeCard`）
struct LockedForecastRangeCard: View {
    var body: some View {
        DashboardCard(title: "見込みの幅", systemImage: "arrow.left.and.right", badge: "Pro") {
            ProLockedContent("見込みの幅は Pro で見られます") {
                VStack(alignment: .leading, spacing: 12) {
                    MetricView("早ければ〜遅くても", text: Text(verbatim: "3/8〜4/2"), unit: "ごろ", size: .medium)
                    MetricView("ペースの幅（1 週間あたり）", text: Text(verbatim: "-0.5〜-0.3"), unit: "kg", size: .medium)
                }
            }
            Text("早め〜遅めの、目標に届く日の幅です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// 「チートデー」カードのぼかし版（本物は `CheatDayCard`）。アプリが提案できる日だけ出します。
struct LockedCheatDayCard: View {
    var body: some View {
        DashboardCard(title: "チートデー", systemImage: "fork.knife.circle", badge: "Pro") {
            Text("予定より先に進んでいます。チートデーの提案があります。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            ProLockedContent("チートデーの提案は Pro で見られます") {
                MetricView("予定より", text: Text(verbatim: "0.8"), unit: "kg 先に進んでいます", size: .large)
            }
            Text("食べ放題の日ではなく、体重を保つ量（維持カロリー）までの日です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            LockedForecastRangeCard()
            LockedCheatDayCard()
            LockedCheatDayCard()
                .dynamicTypeSize(.accessibility2)
                .preferredColorScheme(.dark)
        }
        .padding()
    }
    .environment(ProAccess.previewTrialEnded())
}
