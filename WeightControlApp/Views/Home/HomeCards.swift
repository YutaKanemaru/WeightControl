import SwiftUI

// ホーム画面に並べる「カード」の部品たち。
// どのカードも、計算済みの結果（Logic の値）を受け取って表示するだけです。
// 見た目の共通部品（DashboardCard・MetricView・NoticeLabel）は Views/Components/ にあります。

/// kg を小数 1 桁で表示する書式
private let kgFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
/// 増減（+0.3 / -0.3）を表示する書式
private let signedKgFormat = FloatingPointFormatStyle<Double>.number
    .precision(.fractionLength(1))
    .sign(strategy: .always(includingZero: false))

// MARK: - 体重（いちばん大事な数字）

/// 最新の体重と「目標まで」を大きく出すカード。
///
/// 文字がとても大きい設定のときは、横に並びきらないので `ViewThatFits` で縦並びに切り替えます。
/// （`ViewThatFits` は、最初に書いた並べ方が入りきらなければ次の並べ方を使う、という入れ物です）
struct WeightSummaryCard: View {
    let latestKg: Double
    let latestDate: Date
    /// 目標までの残り（kg）。目標がなければ nil。
    let remainingKg: Double?
    let goalWeightKg: Double?
    /// キープモード中ならキープの範囲。そのときは「目標まで」の代わりに範囲を出す。
    var maintenanceRange: MaintenanceRange? = nil

    var body: some View {
        DashboardCard(title: "体重", systemImage: "scalemass") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline) {
                    latest
                    Spacer(minLength: 16)
                    remaining
                }
                VStack(alignment: .leading, spacing: 12) {
                    latest
                    remaining
                }
            }
        }
    }

    private var latest: some View {
        MetricView(
            "最新の体重",
            value: latestKg,
            unit: "kg",
            caption: Text(latestDate, format: .dateTime.month().day().hour().minute()),
            size: .hero
        )
    }

    @ViewBuilder
    private var remaining: some View {
        if let maintenanceRange {
            MetricView(
                "キープの範囲",
                text: Text("\(maintenanceRange.lowerKg, format: kgFormat)〜\(maintenanceRange.upperKg, format: kgFormat)"),
                unit: "kg",
                caption: Text("中心 \(maintenanceRange.centerKg, format: kgFormat) kg"),
                size: .medium,
                tint: .green
            )
        } else if let remainingKg, let goalWeightKg {
            MetricView(
                "目標まで",
                value: remainingKg,
                unit: "kg",
                caption: Text("目標 \(goalWeightKg, format: kgFormat) kg"),
                size: .medium,
                tint: .green
            )
        }
    }
}

// MARK: - ほめるメッセージ

struct PraiseCard: View {
    let message: PraiseMessage
    let streakDays: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if streakDays > 0 {
                    Text("連続 \(streakDays) 日記録中")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    /// メッセージの種類に合わせたアイコン
    private var symbol: String {
        switch message.kind {
        case .goalAchieved: "trophy.fill"
        case .streakMilestone: "star.fill"
        case .trendTowardGoal, .goalHalfway, .goalProgress: "hand.thumbsup.fill"
        case .trendSteady, .streak: "checkmark.seal.fill"
        case .trendEncouragement, .restart, .maintenanceDrift: "heart.fill"
        case .maintenanceKept: "shield.lefthalf.filled"
        }
    }
}

// MARK: - グラフ

/// 体重のグラフのカード。記録が少ないときの注意書きもここに出します。
struct WeightChartCard: View {
    let dashboard: HomeDashboard
    let goalWeightKg: Double?
    let deadline: Date?
    /// Pro を使えるか。使えないときは、点線の予測と薄い帯を描かない
    /// （点線が目標の横線と交わる所で、目標に届く日が分かってしまうため。docs/PRO.md）
    var isProUnlocked: Bool = true

    var body: some View {
        DashboardCard(title: "体重のグラフ", systemImage: "chart.xyaxis.line") {
            WeightChartView(
                measured: dashboard.trend.map { WeightPoint(date: $0.date, weightKg: $0.measuredKg) },
                paceLine: dashboard.paceLine,
                forecastLine: isProUnlocked ? dashboard.forecastLine : [],
                goalWeightKg: goalWeightKg,
                // キープモード中は期限を使わないので、縦線も出さない
                deadline: dashboard.maintenance == nil ? deadline : nil,
                forecastBand: isProUnlocked ? dashboard.forecastBand : [],
                keepRange: dashboard.maintenance?.range
            )
            if !isProUnlocked, !dashboard.forecastLine.isEmpty {
                ProLockedHint("目標までの点線の予測は Pro で見られます")
            }
            notice
        }
    }

    @ViewBuilder
    private var notice: some View {
        if dashboard.paceRecordedDays == 0 {
            NoticeLabel("直近 3 週間に \(GoalForecaster.minimumRecordedDays) 日分の記録がたまると、ペースの直線と予測を表示します。")
        } else if dashboard.paceRecordedDays < GoalForecaster.reliableRecordedDays, dashboard.forecast == nil {
            // 目標があるときは「達成の見込み」のカードに同じ注意を出すので、ここでは目標がないときだけ出す
            LowAccuracyNotice(recordedDays: dashboard.paceRecordedDays)
        }
    }
}

/// 記録が少ないうち（最初の 1 週間）の「精度が低め」の注意
struct LowAccuracyNotice: View {
    let recordedDays: Int

    var body: some View {
        NoticeLabel(
            text: Text("記録が \(GoalForecaster.reliableRecordedDays) 日分たまるまでは、日々のブレで直線の向きが大きく変わるため、予測の精度は低めです（いま \(recordedDays) 日分）。"),
            style: .caution
        )
    }
}

// MARK: - 達成の見込み

struct ForecastCard: View {
    let forecast: GoalForecastResult
    /// Pro を使えるか。使えないときは「目標に届く日」だけをぼかす（ペースと期限の判定は無料のまま。docs/PRO.md）
    var isProUnlocked: Bool = true

    var body: some View {
        DashboardCard(title: "達成の見込み", systemImage: "flag.checkered") {
            switch forecast {
            case .insufficientData(let recordedDays, let requiredDays):
                VStack(alignment: .leading, spacing: 8) {
                    Text("あと \(max(requiredDays - recordedDays, 1)) 日記録すると、目標に届く日を予測できます。")
                    ProgressView(value: Double(recordedDays), total: Double(requiredDays))
                }
            case .available(let result):
                available(result)
            }
        }
    }

    @ViewBuilder
    private func available(_ forecast: GoalForecast) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch forecast.outcome {
            case .reached:
                MetricView(text: Text("届いています"), caption: Text("目標体重に届いています。おめでとうございます！"), tint: .green)
            case .willReach(let date):
                if isProUnlocked {
                    MetricView(
                        "このペースなら",
                        text: Text(date, format: .dateTime.year().month().day()),
                        unit: "ごろ",
                        caption: Text("目標体重に届く見込みです")
                    )
                } else {
                    // 本当の日付ではなく、決まった見本の文字をぼかす
                    ProLockedContent("目標に届く日は Pro で見られます") {
                        MetricView("このペースなら", text: Text(verbatim: "2027/3/8"), unit: "ごろ", caption: Text("目標体重に届く見込みです"))
                    }
                }
            case .notApproaching:
                VStack(alignment: .leading, spacing: 4) {
                    Text("いまは目標に向かう流れが、まだ見えていません。")
                        .font(.headline)
                    Text("体重は日々上下するものです。記録を続けると、流れが見えてきます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            MetricView(
                "今のペース（1 週間あたり）",
                text: Text(forecast.weeklyChangeKg, format: signedKgFormat),
                unit: "kg",
                size: .medium
            )

            if let status = forecast.deadlineStatus {
                deadlineNotice(status)
            }

            if forecast.confidence == .low {
                LowAccuracyNotice(recordedDays: forecast.recordedDays)
            }
        }
    }

    @ViewBuilder
    private func deadlineNotice(_ status: GoalForecast.DeadlineStatus) -> some View {
        switch status {
        case .onTrack:
            NoticeLabel("期限に間に合うペースです", style: .success)
        case .behind(let requiredWeeklyChangeKg):
            NoticeLabel(text: Text("期限に間に合わせるには、週 \(requiredWeeklyChangeKg, format: signedKgFormat) kg のペースが目安です。"))
        case .passed:
            NoticeLabel("期限の日を過ぎました。目標を見直してみましょう。")
        }
    }
}

// MARK: - 目標がまだないとき

struct GoalPromptCard: View {
    let currentWeightKg: Double?

    var body: some View {
        DashboardCard(title: "目標", systemImage: "flag") {
            Text("目標体重と期限を決めると、目標に届く日の予測と、目標に合わせた摂取カロリーの目安を表示します。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                EditGoalView(goal: nil, currentWeightKg: currentWeightKg)
            } label: {
                Label("目標を決める", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - 記録がまだないとき

struct EmptyRecordsCard: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("まだ記録がありません", systemImage: "scalemass")
        } description: {
            Text("最初の体重を記録すると、ここにグラフが表示されます。\(GoalForecaster.minimumRecordedDays) 日分たまると、ペースの直線と目標に届く日の予測も出ます。")
        } actions: {
            Button("体重を記録する", action: onAdd)
                .buttonStyle(.borderedProminent)
        }
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }
}

// MARK: - 1 日の摂取カロリーの目安

struct IntakeCard: View {
    let intake: IntakeRecommendation
    /// 消費カロリーをどう計算したか（説明文を変えるため）
    var energyChoice: EnergyExpenditureChoice?
    /// 今日がチートデー（Pro）か。そのときは目安を維持カロリー（消費カロリーの目安と同じ量）で出す
    var isCheatDay: Bool = false
    /// キープモード中なら、その状態（見出しを「維持カロリーの目安」などに変える）
    var maintenanceStatus: MaintenanceStatus? = nil

    var body: some View {
        DashboardCard(title: title, systemImage: "fork.knife") {
            if isCheatDay {
                MetricView(
                    value: intake.tdeeKcal.rounded(),
                    fractionLength: 0,
                    unit: "kcal",
                    caption: Text("今日はチートデー。ふだんの日の目安は \(Int(intake.targetKcal.rounded())) kcal")
                )
            } else {
                MetricView(
                    value: intake.targetKcal.rounded(),
                    fractionLength: 0,
                    unit: "kcal",
                    caption: Text("消費カロリーの目安 \(Int(intake.tdeeKcal.rounded())) kcal")
                )
            }
            NoticeLabel(text: sourceText)
            if intake.isRaisedToMinimum && !isCheatDay {
                NoticeLabel("体のために、これより少なくしないよう下限に合わせています。そのぶん、目標のペースより少しゆっくりになります。")
            }
        }
    }

    /// 見出し。キープモード中は、範囲の中なら「維持カロリー」、外なら「ゆっくり戻す」目安と伝える
    private var title: LocalizedStringKey {
        switch maintenanceStatus {
        case nil: "1 日の摂取カロリーの目安"
        case .inRange?, .nearEdge?: "1 日の維持カロリーの目安"
        case .above?, .below?: "ゆっくり範囲に戻すための目安"
        }
    }

    /// 消費カロリーを何から計算したかの説明
    private var sourceText: Text {
        switch energyChoice?.source {
        case .healthKit(let averageActiveEnergyKcal, let days)?:
            return Text("基礎代謝と、ヘルスケアの実績（直近 \(days) 日の平均アクティブエネルギー \(Int(averageActiveEnergyKcal.rounded())) kcal）から計算しています。")
        case .activityLevel?, nil:
            if energyChoice?.isFallback == true {
                return Text("基礎代謝と活動量から計算しています。ヘルスケアの運動データが 7 日分たまると、実績で計算します。")
            } else {
                return Text("基礎代謝と活動量から計算しています。")
            }
        }
    }
}

// MARK: - 無理な目標の修正案

struct GoalCorrectionCard: View {
    let correction: GoalCorrection
    let goal: WeightGoal
    let currentWeightKg: Double?

    var body: some View {
        DashboardCard(title: "目標のペースが少し速めです", systemImage: "exclamationmark.triangle", tint: .orange) {
            Text("体への負担が少ないペースは、週 \(abs(correction.maxWeeklyChangeKg), format: kgFormat) kg くらいまでが目安です。次のどちらかにすると、無理なく続けやすくなります。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                goal.deadline = correction.suggestedDeadline
                // ゆるやか／ハードの提案ではなく、ここで選んだ日付になるので「自分で決める」にする
                goal.paceMode = .manual
            } label: {
                Label("期限を \(correction.suggestedDeadline, format: .dateTime.year().month().day()) にのばす", systemImage: "calendar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            if let suggestedKg = correction.suggestedGoalWeightKg {
                Button {
                    goal.targetWeightKg = suggestedKg
                } label: {
                    Label("今の期限までの目標を \(suggestedKg, format: kgFormat) kg にする", systemImage: "scalemass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            NavigationLink("自分で目標を見直す") {
                EditGoalView(goal: goal, currentWeightKg: currentWeightKg)
            }
            .font(.callout)
        }
    }
}

// MARK: - 目標体重の BMI

/// 保存してある目標体重の BMI が、低め（18.5 未満）か、高め（25 以上）へ増やす目標のときだけ出すカード。
/// この機能を入れる前に決めた目標にも気づけるようにするためです（docs/BMI_GOAL.md）。
struct GoalBMICard: View {
    let advice: GoalBMIAdvice
    let goal: WeightGoal
    let currentWeightKg: Double?

    var body: some View {
        DashboardCard(title: "目標体重を見直してみませんか", systemImage: "figure.stand", tint: .orange) {
            MetricView("目標の BMI", value: advice.goalBMI, caption: Text(advice.goalBand.label), size: .medium, tint: .orange)

            message
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink("目標を見直す") {
                EditGoalView(goal: goal, currentWeightKg: currentWeightKg)
            }
            .font(.callout)

            Text("BMI は大人向けの目安です。医療的な判断ではありません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var message: Text {
        switch advice.verdict {
        case .belowNormal(let suggestedKg):
            Text("やせすぎは体の負担になることがあります。\(suggestedKg, format: kgFormat) kg（BMI 18.5）以上を目安にしてみませんか。")
        case .aboveNormal(let maximumKg, _):
            Text("増やしすぎに気をつけて、\(maximumKg, format: kgFormat) kg（BMI 25 未満）までを目安にしてみませんか。")
        case .normal, .gainingTowardNormal, .firstStep:
            Text("ふつうの範囲（BMI 18.5〜25 未満）は \(advice.normalRangeKg.lowerBound, format: kgFormat)〜\(advice.normalRangeKg.upperBound, format: kgFormat) kg です。")
        }
    }
}

// MARK: - 食べ物ヒント

struct FoodHintCard: View {
    /// 食べ物での言い方（例: りんご1個分）
    let foodPhrase: String
    /// 計画より 1 日あたり多い量（kcal）
    let overPlanKcalPerDay: Double

    var body: some View {
        DashboardCard(title: "ちょっとしたヒント", systemImage: "lightbulb", tint: .yellow) {
            // 細かすぎる数字は気になるので、10 kcal 単位に丸めて「約」をつける
            let roundedKcal = Int((overPlanKcalPerDay / 10).rounded() * 10)
            Text("体重の動きから見ると、計画より 1 日あたり\(foodPhrase)（約 \(roundedKcal) kcal）ほど多めのようです。")
                .fixedSize(horizontal: false, vertical: true)
            Text("おやつや飲み物を少し控えるなど、できそうなことから 1 つ試してみませんか。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
