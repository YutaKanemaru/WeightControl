import Foundation

/// ホーム画面の計算に使うプロフィール（保存データ `UserProfile` から画面側で変換して渡します）。
nonisolated struct DashboardProfile: Equatable, Sendable {
    var heightCm: Double
    var birthYear: Int
    var sex: BiologicalSex
    var activityLevel: ActivityLevel
    /// 消費カロリーを何から計算するか（既定は自動：ヘルスケアの実績があれば実績、なければ活動量）
    var energyMode: EnergyExpenditureMode = .automatic
}

/// ホーム画面の計算に使う目標（保存データ `WeightGoal` から画面側で変換して渡します）。
nonisolated struct DashboardGoal: Equatable, Sendable {
    /// 目標体重（kg）
    var targetWeightKg: Double
    /// 期限
    var deadline: Date
    /// 目標を決めたときの体重（kg）。分からなければ nil（そのときは最初の記録を使います）。
    var startWeightKg: Double?
}

/// ホーム画面に出すものを、まとめて計算した結果。画面はこれを並べるだけにします。
nonisolated struct HomeDashboard: Equatable, Sendable {
    /// グラフ用：1 日 1 件の実績とトレンド（古い順）
    var trend: [TrendPoint]
    /// グラフ用：直近 3 週間の測った体重に引いた直線（実線）。記録が 3 日未満なら空。
    var paceLine: [WeightPoint]
    /// 直線を引いた記録の日数（直近 21 日のうち記録した日数）。直線がなければ 0。
    /// 7 日未満のうちは、グラフに「精度が低め」の注意を出すのに使います。
    var paceRecordedDays: Int
    /// 今の体重の目安（kg）。記録がなければ nil。
    /// 記録が 3 日以上あれば、直近 3 週間の体重に引いた直線の今日の値（`GoalForecaster.paceEstimate`）。
    /// 3 日未満なら、ならした体重（トレンド）の最新の値。
    /// 目標までの残り・進み具合・安全チェック・基礎代謝の計算に使います。
    var currentWeightKg: Double?
    /// 連続記録日数
    var streakDays: Int
    /// いちばん伝えたい「ほめる」メッセージ
    var praise: PraiseMessage
    /// 目標に届く日の予測。目標がなければ nil。
    var forecast: GoalForecastResult?
    /// グラフの点線（今のペースが続いた場合の予測線）。予測できないときは空。
    var forecastLine: [WeightPoint]
    /// 目標のペースが無理なく進められるかどうか。目標か記録がなければ nil。
    var safety: GoalSafetyResult?
    /// 1 日の摂取カロリーの目安。プロフィールか記録がなければ nil。
    var intake: IntakeRecommendation?
    /// 摂取カロリーの目安で使った、消費カロリーの計算方法。プロフィールか記録がなければ nil。
    var energyChoice: EnergyExpenditureChoice?
    /// 体重が計画どおりに減っていないとき、計画より 1 日あたり何 kcal 多いかの目安。
    /// 判断できない（記録が 14 日未満など）か、計画どおりなら nil。
    var overPlanKcalPerDay: Double?
    /// `overPlanKcalPerDay` を身近な食べ物に言いかえたもの（例: りんご 1 個分）。出さないときは nil。
    var calorieHint: CalorieHint?
}

/// ホーム画面のための「とりまとめ役」。
///
/// 新しい計算はせず、すでにある Logic（トレンド・予測・安全チェック・カロリー・メッセージ・食べ物ヒント）を
/// 決まった順番で呼び出して、結果を 1 つの値（`HomeDashboard`）にまとめます。
/// こうしておくと、画面（View）に計算が入り込まず、組み合わせ方もテストで確かめられます。
nonisolated enum HomeDashboardBuilder {
    /// 「ここ最近のトレンドの変化」を何日分で見るか
    static let trendChangeWindowDays = 7
    /// 食べ物ヒントを出すのに必要な記録日数。水分の増減に振り回されないよう、予測より長めに見ます。
    static let foodHintMinimumRecordedDays = 14
    /// これより小さい差なら「目標＝キープ」とみなす（kg）
    static let maintainToleranceKg = 0.1

    static func build(
        points: [WeightPoint],
        profile: DashboardProfile?,
        goal: DashboardGoal?,
        foods: [FoodItem],
        healthActivity: ActivitySummary? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> HomeDashboard {
        let trend = WeightTrendCalculator.trend(points, calendar: calendar)
        // 今の体重の目安：直線（記録 3 日以上）があればその今日の値、なければならした体重
        let pace = GoalForecaster.paceEstimate(points: points, calendar: calendar)
        let currentKg = pace?.currentWeightKg ?? trend.last?.trendKg
        let paceLine = pace.map { ForecastLineBuilder.fittedLine(for: $0, calendar: calendar) } ?? []
        let streak = WeighInStreakCalculator.currentStreak(dates: points.map(\.date), today: now, calendar: calendar)

        // 目標の向きと進み具合
        let startKg = goal?.startWeightKg ?? trend.first?.measuredKg
        let direction: GoalDirection = {
            guard let goal, let startKg else { return .lose }
            return goalDirection(startKg: startKg, targetKg: goal.targetWeightKg)
        }()
        let progress: Double? = {
            guard let goal, let startKg, let currentKg else { return nil }
            return goalProgress(startKg: startKg, currentKg: currentKg, targetKg: goal.targetWeightKg)
        }()

        let praise = PraiseMessageGenerator.primaryMessage(for: PraiseInput(
            trendChangeKg: trendChange(trend, overDays: trendChangeWindowDays, calendar: calendar),
            streakDays: streak,
            goalProgress: progress,
            goalDirection: direction
        ))

        // 予測と点線
        var forecast: GoalForecastResult?
        var forecastLine: [WeightPoint] = []
        if let goal {
            let result = GoalForecaster.forecast(
                points: points,
                goalWeightKg: goal.targetWeightKg,
                deadline: goal.deadline,
                now: now,
                calendar: calendar
            )
            forecast = result
            if case .available(let available) = result {
                forecastLine = ForecastLineBuilder.projection(
                    for: available,
                    goalWeightKg: goal.targetWeightKg,
                    deadline: goal.deadline,
                    calendar: calendar
                )
            }
        }

        // 目標のペースの安全チェック
        var safety: GoalSafetyResult?
        if let goal, let currentKg {
            safety = GoalSafetyChecker.check(
                currentWeightKg: currentKg,
                goalWeightKg: goal.targetWeightKg,
                deadline: goal.deadline,
                now: now,
                calendar: calendar
            )
        }
        // 目標がなければ「今の体重をキープ」として計算する
        let plannedWeeklyChangeKg = safety?.plannedWeeklyChangeKg ?? 0

        // 1 日の摂取カロリーの目安
        var intake: IntakeRecommendation?
        var energyChoice: EnergyExpenditureChoice?
        if let profile, let currentKg {
            let bmr = CalorieCalculator.basalMetabolicRate(
                weightKg: currentKg,
                heightCm: profile.heightCm,
                ageYears: CalorieCalculator.ageYears(birthYear: profile.birthYear, on: now, calendar: calendar),
                sex: profile.sex
            )
            // 消費カロリーは、設定に合わせて「活動係数」か「ヘルスケアの実績」で計算する
            let choice = EnergyExpenditureResolver.choose(
                mode: profile.energyMode,
                activityLevel: profile.activityLevel,
                healthActivity: healthActivity
            )
            energyChoice = choice
            let tdee = EnergyExpenditureResolver.totalDailyEnergyExpenditure(bmrKcal: bmr, source: choice.source)
            intake = CalorieCalculator.recommendedIntake(
                tdeeKcal: tdee,
                bmrKcal: bmr,
                sex: profile.sex,
                plannedWeeklyChangeKg: plannedWeeklyChangeKg
            )
        }

        // 計画より食べすぎていないか（体重の動きから逆算）。
        // 水分の増減に振り回されないよう、14 日分の記録があるときだけ出します。
        // 増量が目標のときは「計画より多い」は悪いことではないので出しません。
        var overPlan: Double?
        var hint: CalorieHint?
        if case .available(let available)? = forecast,
           available.recordedDays >= foodHintMinimumRecordedDays,
           direction != .gain,
           safety != nil {
            let estimate = EnergyBalanceEstimator.estimate(
                observedWeeklyChangeKg: available.weeklyChangeKg,
                plannedWeeklyChangeKg: plannedWeeklyChangeKg,
                tdeeKcal: intake?.tdeeKcal
            )
            let result = CalorieHintGenerator.hint(forSurplusKcal: estimate.overPlanKcalPerDay, foods: foods)
            if case .over = result {
                overPlan = estimate.overPlanKcalPerDay
                hint = result
            }
        }

        return HomeDashboard(
            trend: trend,
            paceLine: paceLine,
            paceRecordedDays: pace?.recordedDays ?? 0,
            currentWeightKg: currentKg,
            streakDays: streak,
            praise: praise,
            forecast: forecast,
            forecastLine: forecastLine,
            safety: safety,
            intake: intake,
            energyChoice: energyChoice,
            overPlanKcalPerDay: overPlan,
            calorieHint: hint
        )
    }

    /// ここ `days` 日でトレンドがどれだけ動いたか（kg、マイナスは減少）。
    /// `days` 日以上前のトレンドがまだなければ nil（比べる相手がないため）。
    static func trendChange(_ trend: [TrendPoint], overDays days: Int, calendar: Calendar = .current) -> Double? {
        guard let latest = trend.last else { return nil }
        // `days` 日以上前の点のうち、いちばん新しいものと比べる
        guard let baseline = trend.last(where: {
            DayMath.days(from: $0.date, to: latest.date, calendar: calendar) >= days
        }) else { return nil }
        return latest.trendKg - baseline.trendKg
    }

    /// 目標の向き（減らす・増やす・キープ）
    static func goalDirection(startKg: Double, targetKg: Double) -> GoalDirection {
        let diff = targetKg - startKg
        if abs(diff) <= maintainToleranceKg { return .maintain }
        return diff < 0 ? .lose : .gain
    }

    /// 目標までの進み具合（0 = スタート、1 = 達成）。キープが目標なら nil。
    /// 逆方向に動いたときはマイナスにせず 0 にします。
    static func goalProgress(startKg: Double, currentKg: Double, targetKg: Double) -> Double? {
        let total = targetKg - startKg
        guard abs(total) > maintainToleranceKg else { return nil }
        return max(0, (currentKg - startKg) / total)
    }
}
