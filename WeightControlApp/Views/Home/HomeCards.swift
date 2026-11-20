import SwiftUI

// ホーム画面に並べる「カード」の部品たち。
// どのカードも、計算済みの結果（Logic の値）を受け取って表示するだけです。

/// 角丸の背景つきの入れ物
struct DashboardCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

/// kg を小数 1 桁で表示する書式
private let kgFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
/// 増減（+0.3 / -0.3）を表示する書式
private let signedKgFormat = FloatingPointFormatStyle<Double>.number
    .precision(.fractionLength(1))
    .sign(strategy: .always(includingZero: false))

// MARK: - ほめるメッセージ

struct PraiseCard: View {
    let message: PraiseMessage
    let streakDays: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.body)
                if streakDays > 0 {
                    Text("連続 \(streakDays) 日記録中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    /// メッセージの種類に合わせたアイコン
    private var symbol: String {
        switch message.kind {
        case .goalAchieved: "trophy.fill"
        case .streakMilestone: "star.fill"
        case .trendTowardGoal, .goalHalfway, .goalProgress: "hand.thumbsup.fill"
        case .trendSteady, .streak: "checkmark.seal.fill"
        case .trendEncouragement, .restart: "heart.fill"
        }
    }
}

// MARK: - 達成の見込み

struct ForecastCard: View {
    /// 予測の結果。目標がなければ nil。
    let forecast: GoalForecastResult?

    var body: some View {
        DashboardCard(title: "達成の見込み", systemImage: "flag.checkered") {
            switch forecast {
            case nil:
                Text("目標を決めると、目標体重に届く日を予測します。")
                    .foregroundStyle(.secondary)
            case .insufficientData(let recordedDays, let requiredDays)?:
                VStack(alignment: .leading, spacing: 6) {
                    Text("あと \(max(requiredDays - recordedDays, 1)) 日記録すると、目標に届く日を予測できます。")
                    ProgressView(value: Double(recordedDays), total: Double(requiredDays))
                }
            case .available(let result)?:
                available(result)
            }
        }
    }

    @ViewBuilder
    private func available(_ forecast: GoalForecast) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch forecast.outcome {
            case .reached:
                Text("目標体重に届いています！")
                    .font(.title3.bold())
            case .willReach(let date):
                Text("\(date, format: .dateTime.year().month().day()) ごろ")
                    .font(.title3.bold())
                Text("このペースが続くと、目標体重に届く見込みです。")
            case .notApproaching:
                Text("いまは目標に向かう流れが、まだ見えていません。")
                Text("体重は日々上下するものです。記録を続けると、流れが見えてきます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("今のペース：週 \(forecast.weeklyChangeKg, format: signedKgFormat) kg")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            if let status = forecast.deadlineStatus {
                deadlineText(status)
                    .font(.callout)
            }

            if forecast.confidence == .reference {
                Label("記録が \(GoalForecaster.reliableRecordedDays) 日分たまるまでは参考値です（いま \(forecast.recordedDays) 日分）", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func deadlineText(_ status: GoalForecast.DeadlineStatus) -> some View {
        switch status {
        case .onTrack:
            Label("期限に間に合うペースです", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .behind(let requiredWeeklyChangeKg):
            Text("期限に間に合わせるには、週 \(requiredWeeklyChangeKg, format: signedKgFormat) kg のペースが目安です。")
        case .passed:
            Text("期限の日を過ぎました。目標を見直してみましょう。")
        }
    }
}

// MARK: - 1 日の摂取カロリーの目安

struct IntakeCard: View {
    let intake: IntakeRecommendation
    /// 消費カロリーをどう計算したか（説明文を変えるため）
    var energyChoice: EnergyExpenditureChoice?

    var body: some View {
        DashboardCard(title: "1 日の摂取カロリーの目安", systemImage: "fork.knife") {
            Text("\(Int(intake.targetKcal.rounded())) kcal")
                .font(.largeTitle.bold().monospacedDigit())
            Text("消費カロリーの目安 \(Int(intake.tdeeKcal.rounded())) kcal")
                .font(.caption)
                .foregroundStyle(.secondary)
            sourceText
                .font(.caption)
                .foregroundStyle(.secondary)
            if intake.isRaisedToMinimum {
                Label("体のために、これより少なくしないよう下限に合わせています。そのぶん、目標のペースより少しゆっくりになります。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension IntakeCard {
    /// 消費カロリーを何から計算したかの説明
    @ViewBuilder
    fileprivate var sourceText: some View {
        switch energyChoice?.source {
        case .healthKit(let averageActiveEnergyKcal, let days)?:
            Text("（基礎代謝と、ヘルスケアの実績：直近 \(days) 日の平均アクティブエネルギー \(Int(averageActiveEnergyKcal.rounded())) kcal から計算）")
        case .activityLevel?, nil:
            if energyChoice?.isFallback == true {
                Text("（基礎代謝と活動量から計算。ヘルスケアの運動データが 7 日分たまると、実績で計算します）")
            } else {
                Text("（基礎代謝と活動量から計算）")
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

            Button {
                goal.deadline = correction.suggestedDeadline
            } label: {
                Label("期限を \(correction.suggestedDeadline, format: .dateTime.year().month().day()) にのばす", systemImage: "calendar")
            }
            .buttonStyle(.bordered)

            if let suggestedKg = correction.suggestedGoalWeightKg {
                Button {
                    goal.targetWeightKg = suggestedKg
                } label: {
                    Label("今の期限までの目標を \(suggestedKg, format: kgFormat) kg にする", systemImage: "scalemass")
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
            Text("体重の流れから見ると、計画より 1 日あたり\(foodPhrase)（約 \(roundedKcal) kcal）ほど多めのようです。")
            Text("おやつや飲み物を少し控えるなど、できそうなことから 1 つ試してみませんか。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
