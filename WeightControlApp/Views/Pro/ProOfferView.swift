import SwiftUI

/// Pro の説明と「1 か月無料で試す」の画面。仕様は docs/PRO.md。
///
/// ぼかしたカードの「Pro で見られます」、ホームのお試しのカード、設定タブの「Pro について」から開きます。
///
/// ## App Store の決まりに合わせていること（審査ガイドライン 3.1.1）
/// お試しを始める前に、次の 3 つをはっきり書きます。
/// 1. お試しの長さ（1 か月）
/// 2. お試しが終わると、見られなくなるもの
/// 3. 続けて使うのに必要なお金（買い切りの Pro。自動で料金がかかることはない）
///
/// 購入ボタンと「購入を復元」は、課金（フェーズ 11・StoreKit）を入れるときにここへ足します。
struct ProOfferView: View {
    @Environment(ProAccess.self) private var pro: ProAccess?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }

                Section("Pro でできること") {
                    InfoPointRow(
                        title: "目標に届く日",
                        detail: "このペースなら何日ごろ目標に届くかと、グラフの点線の予測が見られます。",
                        systemImage: "flag.checkered"
                    )
                    InfoPointRow(
                        title: "見込みの幅",
                        detail: "「早ければ〜遅くても」の幅と、グラフの薄い帯が見られます。",
                        systemImage: "arrow.left.and.right"
                    )
                    InfoPointRow(
                        title: "チートデーの提案",
                        detail: "予定より先に進んでいるとき、維持カロリーまで食べてよい日をアプリが提案します。食べ放題の日ではありません。",
                        systemImage: "fork.knife.circle"
                    )
                }

                Section {
                    statusContent
                } footer: {
                    Text("記録・グラフ・今のペース・期限に間に合うかの判定・カロリーの目安・カレンダー・通知は、ずっと無料で使えます。")
                }
            }
            .navigationTitle("Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("体重予報 Pro", systemImage: "star.circle.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.accentColor)
            Text("目標に届く日まで見通して、続けやすく。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch pro?.status() ?? .trialAvailable {
        case .trialAvailable:
            Button {
                pro?.startTrial()
            } label: {
                Label("1 か月無料で試す", systemImage: "gift")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            Text("お試しは 1 か月で終わります。終わると、目標に届く日・点線の予測・見込みの幅・チートデーの提案は、ぼかして表示されます。自動で料金がかかることはありません。続けて使うには、Pro（買い切り）の購入が必要です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .trial(let endsAt, let daysLeft):
            LabeledContent("お試し中") {
                Text("あと \(daysLeft) 日")
                    .monospacedDigit()
            }
            Text("\(lastDay(endsAt), format: .dateTime.month().day()) まで使えます。終わっても、自動で料金がかかることはありません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            purchasePlaceholder
        case .trialEnded:
            Text("お試し期間は終わりました。記録やグラフは、このまま無料で使えます。")
                .font(.callout)
            purchasePlaceholder
        case .purchased:
            Label("購入済みです。ありがとうございます！", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .debugUnlocked:
            Label("開発用の「Pro を試す」で使っています", systemImage: "hammer")
        }
    }

    /// 課金（フェーズ 11）を入れるまでの、購入ボタンの代わり
    private var purchasePlaceholder: some View {
        Label("購入のしくみは準備中です", systemImage: "clock")
            .foregroundStyle(.secondary)
    }

    /// お試しの最後の日（終わる日時は次の日の 0 時なので、その前の日）
    private func lastDay(_ endsAt: Date) -> Date {
        DayMath.date(byAddingDays: -1, to: endsAt, calendar: .current)
    }
}

#Preview("まだ始めていない") {
    ProOfferView()
        .environment(ProAccess(defaults: UserDefaults(suiteName: "preview.pro.offer") ?? .standard))
}

#Preview("お試し終了") {
    ProOfferView()
        .environment(ProAccess.previewTrialEnded())
}

#Preview("大きい文字・ダークモード") {
    ProOfferView()
        .environment(ProAccess.previewTrialEnded())
        .dynamicTypeSize(.accessibility2)
        .preferredColorScheme(.dark)
}
