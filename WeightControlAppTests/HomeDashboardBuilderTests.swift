import Foundation
import Testing
@testable import WeightControlApp

/// ホーム画面のとりまとめ役（HomeDashboardBuilder）のテスト。
/// 個々の計算は各ロジックのテストで確かめているので、ここでは「正しく組み合わせているか」を見ます。
struct HomeDashboardBuilderTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    private let profile = DashboardProfile(heightCm: 170, birthYear: 1990, sex: .male, activityLevel: .sedentary)
    private let apple = FoodItem(id: "apple", name: "りんご", unit: "個", portion: "中1個", kcal: 130, category: .fruit)
    private let banana = FoodItem(id: "banana", name: "バナナ", unit: "本", portion: "中1本", kcal: 90, category: .fruit)
    private var foods: [FoodItem] { [apple, banana] }

    /// `days` 日分、毎日 `weightKg(n)` の記録
    private func points(days: Int, _ weightKg: (Int) -> Double) -> [WeightPoint] {
        (0..<days).map { WeightPoint(date: day($0), weightKg: weightKg($0)) }
    }

    private func build(
        _ points: [WeightPoint],
        profile: DashboardProfile? = nil,
        goal: DashboardGoal? = nil,
        includesPro: Bool = false,
        cheatDays: [Date] = [],
        now: Date
    ) -> HomeDashboard {
        HomeDashboardBuilder.build(
            points: points, profile: profile, goal: goal, foods: foods,
            includesPro: includesPro, cheatDays: cheatDays, now: now, calendar: calendar
        )
    }

    // MARK: - 記録や設定が足りないとき

    @Test("記録がなければ、再開をうながすメッセージだけ出す")
    func noRecords() {
        let dashboard = build([], profile: profile, goal: DashboardGoal(targetWeightKg: 60, deadline: day(90)), now: day(0))
        #expect(dashboard.trend.isEmpty)
        #expect(dashboard.currentWeightKg == nil)
        #expect(dashboard.streakDays == 0)
        #expect(dashboard.praise.kind == .restart)
        #expect(dashboard.forecast == .insufficientData(recordedDays: 0, requiredDays: 3))
        #expect(dashboard.forecastLine.isEmpty)
        #expect(dashboard.paceLine.isEmpty)
        #expect(dashboard.paceRecordedDays == 0)
        #expect(dashboard.safety == nil)
        #expect(dashboard.intake == nil)
        #expect(dashboard.calorieHint == nil)
    }

    @Test("目標がなければ予測はせず、カロリーは「今の体重をキープ」で計算する")
    func noGoal() throws {
        let records = points(days: 5) { _ in 70 }
        let dashboard = build(records, profile: profile, now: day(4))
        #expect(dashboard.forecast == nil)
        #expect(dashboard.forecastLine.isEmpty)
        #expect(dashboard.safety == nil)
        // 目標がなくても、これまでの記録の直線はグラフに描く
        #expect(dashboard.paceLine.count == 2)
        #expect(dashboard.paceRecordedDays == 5)

        let bmr = CalorieCalculator.basalMetabolicRate(weightKg: 70, heightCm: 170, ageYears: 37, sex: .male)
        let expected = CalorieCalculator.recommendedIntake(
            tdeeKcal: bmr * ActivityLevel.sedentary.factor,
            bmrKcal: bmr,
            sex: .male,
            plannedWeeklyChangeKg: 0
        )
        let intake = try #require(dashboard.intake)
        #expect(isApproximately(intake.targetKcal, expected.targetKcal))
        #expect(isApproximately(intake.dailyBalanceKcal, 0))
    }

    @Test("プロフィールがなければカロリーの目安は出さない")
    func noProfile() {
        let dashboard = build(points(days: 5) { _ in 70 }, now: day(4))
        #expect(dashboard.intake == nil)
    }

    @Test("ヘルスケアの実績があれば（自動）、消費カロリーは（基礎代謝 ＋ アクティブエネルギー）÷ 0.9 で計算する")
    func usesHealthActivityAutomatically() throws {
        let activity = ActivitySummary(dayCount: 10, averageSteps: 9000, averageActiveEnergyKcal: 450,
                                       averageActiveMinutes: 40, suggestedLevel: .moderate)
        let dashboard = HomeDashboardBuilder.build(
            points: points(days: 5) { _ in 70 }, profile: profile, goal: nil, foods: foods,
            healthActivity: activity, now: day(4), calendar: calendar
        )
        let bmr = CalorieCalculator.basalMetabolicRate(weightKg: 70, heightCm: 170, ageYears: 37, sex: .male)
        let intake = try #require(dashboard.intake)
        #expect(isApproximately(intake.tdeeKcal, (bmr + 450) / 0.9, tolerance: 1e-6))
        #expect(dashboard.energyChoice?.source == .healthKit(averageActiveEnergyKcal: 450, days: 10))
    }

    @Test("活動量を選んでいれば、ヘルスケアの実績があっても 基礎代謝 × 活動係数 で計算する")
    func activityLevelModeIgnoresHealth() throws {
        let activity = ActivitySummary(dayCount: 10, averageSteps: 9000, averageActiveEnergyKcal: 450,
                                       averageActiveMinutes: 40, suggestedLevel: .moderate)
        var manual = profile
        manual.energyMode = .activityLevel
        let dashboard = HomeDashboardBuilder.build(
            points: points(days: 5) { _ in 70 }, profile: manual, goal: nil, foods: foods,
            healthActivity: activity, now: day(4), calendar: calendar
        )
        let bmr = CalorieCalculator.basalMetabolicRate(weightKg: 70, heightCm: 170, ageYears: 37, sex: .male)
        let intake = try #require(dashboard.intake)
        #expect(isApproximately(intake.tdeeKcal, bmr * ActivityLevel.sedentary.factor, tolerance: 1e-6))
        #expect(dashboard.energyChoice?.source == .activityLevel(.sedentary))
    }

    // MARK: - 予測とグラフ

    @Test("順調に減っていれば予測線が目標体重で終わり、食べ物ヒントは出ない")
    func steadyLoss() throws {
        let records = points(days: 21) { 80 - 0.1 * Double($0) }
        let goal = DashboardGoal(targetWeightKg: 75, deadline: day(200), startWeightKg: 80)
        let dashboard = build(records, profile: profile, goal: goal, now: day(20))

        guard case .available(let forecast)? = dashboard.forecast else {
            Issue.record("予測が出ていない: \(String(describing: dashboard.forecast))")
            return
        }
        #expect(forecast.confidence == .reliable)
        #expect(dashboard.trend.count == 21)
        // 実線（これまでの直線）の終わりと、点線（予測）の始まりがつながる
        #expect(dashboard.paceLine.last == dashboard.forecastLine.first)
        let last = try #require(dashboard.forecastLine.last)
        // 点線の最後は目標体重（日単位で切り上げるので、ほぼ目標体重）
        #expect(isApproximately(last.weightKg, 75, tolerance: 0.15))
        if case .safe? = dashboard.safety {} else {
            Issue.record("無理のない目標のはず: \(String(describing: dashboard.safety))")
        }
        #expect(dashboard.calorieHint == nil)
        #expect(dashboard.overPlanKcalPerDay == nil)
        #expect(dashboard.streakDays == 21)
    }

    // MARK: - 食べ物ヒント

    @Test("体重が横ばいで計画より減っていなければ、オーバー分を食べ物で示す")
    func flatWeightShowsFoodHint() throws {
        // 期限まで 70 日 = 10 週。2 kg 減らすには 0.2 kg/週 → 1 日あたり約 206 kcal 分の差
        let records = points(days: 21) { _ in 70 }
        let goal = DashboardGoal(targetWeightKg: 68, deadline: day(90), startWeightKg: 70)
        let dashboard = build(records, profile: profile, goal: goal, now: day(20))

        let overPlan = try #require(dashboard.overPlanKcalPerDay)
        #expect(isApproximately(overPlan, 0.2 * 7200 / 7, tolerance: 1e-6))
        let hint = try #require(dashboard.calorieHint)
        #expect(hint.foodPhrase != nil)
    }

    @Test("記録が 14 日未満のうちは（予測が出ていても）、食べ物ヒントを出さない")
    func noFoodHintWithFewRecords() {
        let records = points(days: 10) { _ in 70 }
        let goal = DashboardGoal(targetWeightKg: 68, deadline: day(90), startWeightKg: 70)
        let dashboard = build(records, profile: profile, goal: goal, now: day(9))
        #expect(dashboard.calorieHint == nil)
    }

    @Test("増量が目標のときは、食べ物ヒントを出さない")
    func noFoodHintWhenGaining() {
        let records = points(days: 21) { _ in 60 }
        let goal = DashboardGoal(targetWeightKg: 62, deadline: day(120), startWeightKg: 60)
        let dashboard = build(records, profile: profile, goal: goal, now: day(20))
        #expect(dashboard.calorieHint == nil)
    }

    // MARK: - 無理な目標

    @Test("ペースが速すぎる目標なら修正案を出し、カロリーは無理のないペースで計算する")
    func tooAggressiveGoal() throws {
        let records = points(days: 3) { _ in 70 }
        let goal = DashboardGoal(targetWeightKg: 60, deadline: day(32), startWeightKg: 70)
        let dashboard = build(records, profile: profile, goal: goal, now: day(2))

        guard case .tooAggressive(let correction)? = dashboard.safety else {
            Issue.record("修正案が出ていない: \(String(describing: dashboard.safety))")
            return
        }
        #expect(isApproximately(correction.maxWeeklyChangeKg, -0.7))
        let intake = try #require(dashboard.intake)
        // 0.7 kg/週 減らすペース = 1 日 -720 kcal（下限に引っかからなければ）
        if !intake.isRaisedToMinimum {
            #expect(isApproximately(intake.dailyBalanceKcal, -720, tolerance: 1e-6))
        }
    }

    // MARK: - 小さな計算

    @Test("トレンドの変化は 7 日以上前の点と比べる。足りなければ nil")
    func trendChange() {
        let short = WeightTrendCalculator.trend(points(days: 7) { 70 - 0.1 * Double($0) }, calendar: calendar)
        #expect(HomeDashboardBuilder.trendChange(short, overDays: 7, calendar: calendar) == nil)

        let long = WeightTrendCalculator.trend(points(days: 8) { 70 - 0.1 * Double($0) }, calendar: calendar)
        let change = HomeDashboardBuilder.trendChange(long, overDays: 7, calendar: calendar)
        #expect(change.map { $0 < 0 } == true)
    }

    @Test("目標の向き", arguments: [
        (70.0, 65.0, GoalDirection.lose),
        (60.0, 62.0, GoalDirection.gain),
        (70.0, 70.05, GoalDirection.maintain),
    ])
    func direction(start: Double, target: Double, expected: GoalDirection) {
        #expect(HomeDashboardBuilder.goalDirection(startKg: start, targetKg: target) == expected)
    }

    @Test("進み具合は 0〜1、逆方向に動いたら 0、キープなら nil")
    func progress() {
        #expect(HomeDashboardBuilder.goalProgress(startKg: 70, currentKg: 67.5, targetKg: 65).map { isApproximately($0, 0.5) } == true)
        #expect(HomeDashboardBuilder.goalProgress(startKg: 70, currentKg: 71, targetKg: 65) == 0)
        #expect(HomeDashboardBuilder.goalProgress(startKg: 70, currentKg: 70, targetKg: 70) == nil)
    }

    // MARK: - BMI

    @Test("目標とプロフィールがあれば、目標体重の BMI の目安を出す")
    func goalBMI() throws {
        let records = points(days: 5) { _ in 60 }
        // 170 cm で 50 kg は BMI 17.3。BMI 18.5 の体重は 53.5 kg
        let lowGoal = DashboardGoal(targetWeightKg: 50, deadline: day(200), startWeightKg: 60)
        let low = try #require(build(records, profile: profile, goal: lowGoal, now: day(4)).goalBMI)
        #expect(low.verdict == .belowNormal(suggestedWeightKg: 53.5))
        #expect(low.needsHomeAttention)

        let normalGoal = DashboardGoal(targetWeightKg: 58, deadline: day(200), startWeightKg: 60)
        let normal = try #require(build(records, profile: profile, goal: normalGoal, now: day(4)).goalBMI)
        #expect(normal.verdict == .normal)
        #expect(normal.needsHomeAttention == false)

        // プロフィールか目標がなければ出さない
        #expect(build(records, goal: lowGoal, now: day(4)).goalBMI == nil)
        #expect(build(records, profile: profile, now: day(4)).goalBMI == nil)
    }

    // MARK: - 摂取カロリーの下限

    @Test("プロフィールと記録があれば、摂取カロリーの下限も出す（男性は 1500 kcal 以上）")
    func minimumIntake() throws {
        let records = points(days: 5) { _ in 70 }
        let dashboard = build(records, profile: profile, now: day(4))
        let minimum = try #require(dashboard.minimumIntakeKcal)
        let intake = try #require(dashboard.intake)
        #expect(minimum >= 1500)
        #expect(intake.targetKcal >= minimum)
        #expect(build(records, now: day(4)).minimumIntakeKcal == nil)
    }

    // MARK: - Pro

    @Test("Pro を使わないときは、幅付きの予測も帯も出さない")
    func proIsOffByDefault() {
        let records = points(days: 21) { 80 - 0.1 * Double($0) }
        let goal = DashboardGoal(targetWeightKg: 75, deadline: day(90))
        let dashboard = build(records, profile: profile, goal: goal, now: day(20))
        #expect(dashboard.forecastRange == nil)
        #expect(dashboard.forecastBand.isEmpty)
    }

    @Test("Pro なら幅付きの予測と帯を出す。まん中の日は無料版と同じで、帯は今の体重の目安から始まる")
    func proForecastRange() throws {
        let records = points(days: 21) { 80 - 0.1 * Double($0) }
        let goal = DashboardGoal(targetWeightKg: 75, deadline: day(90))
        let dashboard = build(records, profile: profile, goal: goal, includesPro: true, now: day(20))

        guard case .available(let range)? = dashboard.forecastRange,
              case .available(let forecast)? = dashboard.forecast,
              case .willReach(let date) = forecast.outcome else {
            Issue.record("幅付きの予測が出ていない: \(String(describing: dashboard.forecastRange))")
            return
        }
        #expect(range.expectedDate == date)
        let first = try #require(dashboard.forecastBand.first)
        #expect(first.date == forecast.latestDate)
        #expect(isApproximately(first.lowerKg, forecast.currentWeightKg, tolerance: 1e-6))
        #expect(isApproximately(first.upperKg, forecast.currentWeightKg, tolerance: 1e-6))
        // 無料版の結果は Pro でも変わらない
        let free = build(records, profile: profile, goal: goal, now: day(20))
        #expect(free.forecast == dashboard.forecast)
        #expect(free.forecastLine == dashboard.forecastLine)
    }

    /// チートデーの提案用：0 日目に 80 kg で目標を決め、毎日 0.1 kg ずつ減っている（20 日目に 78 kg）。
    /// 目標 75 kg・期限 90 日目なので、予定の線の 20 日目は 80 − 5 × 20 ÷ 90 ≒ 78.89 kg → 貯金 約 0.89 kg。
    private var cheatDayRecords: [WeightPoint] { points(days: 21) { 80 - 0.1 * Double($0) } }
    private var cheatDayGoal: DashboardGoal {
        DashboardGoal(targetWeightKg: 75, deadline: day(90), startWeightKg: 80, startDate: day(0))
    }

    @Test("Pro：予定より先に進んでいればチートデーを提案する。無料版の結果は変わらない")
    func proCheatDaySuggestion() throws {
        let dashboard = build(cheatDayRecords, profile: profile, goal: cheatDayGoal, includesPro: true, now: day(20))
        let suggestion = try #require(dashboard.cheatDaySuggestion?.suggestion)
        #expect(isApproximately(suggestion.aheadKg, 80 - 5.0 * 20 / 90 - 78, tolerance: 1e-6))
        #expect(suggestion.suggestedDays == 2)
        let intake = try #require(dashboard.intake)
        #expect(suggestion.cheatDayKcal == intake.tdeeKcal)
        #expect(suggestion.regularDayKcal == intake.targetKcal)
        #expect(!dashboard.isCheatDayToday)

        let free = build(cheatDayRecords, profile: profile, goal: cheatDayGoal, now: day(20))
        #expect(free.cheatDaySuggestion == nil)
        #expect(free.intake == dashboard.intake)
        #expect(free.forecast == dashboard.forecast)
    }

    @Test("Pro：今日をチートデーにすると、今日がチートデーになり、提案は残り 1 日になる")
    func proCheatDayToday() throws {
        let dashboard = build(
            cheatDayRecords, profile: profile, goal: cheatDayGoal,
            includesPro: true, cheatDays: [day(20)], now: day(20)
        )
        #expect(dashboard.isCheatDayToday)
        #expect(dashboard.cheatDaySuggestion?.suggestion?.suggestedDays == 1)
        // 無料版では、保存したチートデーがあっても「今日はチートデー」にしない
        let free = build(cheatDayRecords, profile: profile, goal: cheatDayGoal, cheatDays: [day(20)], now: day(20))
        #expect(!free.isCheatDayToday)
    }

    @Test("Pro でも、目標を決めた日が分からなければチートデーは提案しない")
    func proCheatDayWithoutStartDate() {
        var goal = cheatDayGoal
        goal.startDate = nil
        let dashboard = build(cheatDayRecords, profile: profile, goal: goal, includesPro: true, now: day(20))
        #expect(dashboard.cheatDaySuggestion == nil)
    }

    @Test("Pro でも、目標がなければ幅付きの予測は出さない")
    func proWithoutGoal() {
        let records = points(days: 21) { 80 - 0.1 * Double($0) }
        let dashboard = build(records, profile: profile, includesPro: true, now: day(20))
        #expect(dashboard.forecastRange == nil)
        #expect(dashboard.forecastBand.isEmpty)
    }
}
