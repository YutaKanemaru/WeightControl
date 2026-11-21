import Foundation
import Testing
@testable import WeightControlApp

/// チートデーの提案（CheatDaySuggestionAdvisor）のテスト。決まりは docs/CHEAT_DAY.md。
///
/// 基本の形（docs の例と同じ数字）：
/// - 30 日前に 72 kg で目標を決めた。目標 68 kg・期限は 70 日後（全体 100 日）
/// - 予定の線の今日の値 ＝ 72 − 4 × 30 ÷ 100 ＝ 70.8 kg
/// - 今の体重の目安 70.0 kg → 貯金 0.8 kg
/// - 維持カロリー 2,300 kcal・ふだんの目安 1,800 kcal → チートデー 1 日のコスト 500 ÷ 7200 ≒ 0.069 kg
struct CheatDaySuggestionAdvisorTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }
    /// 「今日」＝ 基準日の昼 12 時
    private let now = TestCalendar.day(0, hour: 12)

    private let goal = CheatDayGoal(targetWeightKg: 68, deadline: TestCalendar.day(70), startDate: TestCalendar.day(-30), startWeightKg: 72)
    private let intake = IntakeRecommendation(tdeeKcal: 2300, targetKcal: 1800, dailyBalanceKcal: -500, isRaisedToMinimum: false)

    private func forecast(
        currentKg: Double = 70.0,
        recordedDays: Int = 21,
        deadlineStatus: GoalForecast.DeadlineStatus? = .onTrack
    ) -> GoalForecast {
        GoalForecast(
            confidence: recordedDays >= 7 ? .reliable : .low,
            recordedDays: recordedDays,
            latestDate: day(0),
            currentWeightKg: currentKg,
            weeklyChangeKg: -0.5,
            outcome: .willReach(on: day(30)),
            deadlineStatus: deadlineStatus
        )
    }

    private func suggest(
        points: [WeightPoint] = [],
        goal: CheatDayGoal? = nil,
        forecast: GoalForecast? = nil,
        intake: IntakeRecommendation? = nil,
        cheatDays: [Date] = []
    ) -> CheatDaySuggestionResult {
        CheatDaySuggestionAdvisor.suggest(
            points: points,
            goal: goal ?? self.goal,
            forecast: forecast ?? self.forecast(),
            intake: intake ?? self.intake,
            cheatDays: cheatDays,
            now: now,
            calendar: calendar
        )
    }

    private func suggested(_ result: CheatDaySuggestionResult) throws -> CheatDaySuggestion {
        guard case .suggested(let suggestion) = result else {
            Issue.record("提案が出ていません: \(result)")
            throw CancellationError()
        }
        return suggestion
    }

    // MARK: - 提案する

    @Test("予定より 0.8 kg 先に進んでいれば、2 日使っても 0.5 kg 以上残るので「2 日まで」")
    func suggestsTwoDays() throws {
        let suggestion = try suggested(suggest())
        #expect(isApproximately(suggestion.plannedWeightKg, 70.8))
        #expect(isApproximately(suggestion.aheadKg, 0.8))
        #expect(suggestion.currentWeightKg == 70.0)
        #expect(suggestion.suggestedDays == 2)
        #expect(suggestion.cheatDayKcal == 2300)
        #expect(suggestion.regularDayKcal == 1800)
        #expect(isApproximately(suggestion.costKgPerDay, 500.0 / 7200.0))
        #expect(suggestion.selectableDates == (0..<7).map { day($0) })
    }

    @Test("貯金 0.6 kg：2 日使うと 0.5 kg を下回るので「1 日」")
    func suggestsOneDay() throws {
        let suggestion = try suggested(suggest(forecast: forecast(currentKg: 70.2)))
        #expect(isApproximately(suggestion.aheadKg, 0.6, tolerance: 1e-9))
        #expect(suggestion.suggestedDays == 1)
    }

    @Test("貯金 0.51 kg なら提案する（0.5 kg 以上）")
    func justAboveMinimumAhead() throws {
        let suggestion = try suggested(suggest(forecast: forecast(currentKg: 70.29)))
        #expect(suggestion.suggestedDays == 1)
    }

    @Test("開始の体重がなければ、目標を決めた日以降の最初の記録を使う")
    func startWeightFromFirstRecord() throws {
        let points = [
            WeightPoint(date: TestCalendar.day(-40, hour: 7), weightKg: 75),  // 目標を決める前なので使わない
            WeightPoint(date: TestCalendar.day(-30, hour: 7), weightKg: 72),
            WeightPoint(date: TestCalendar.day(-29, hour: 7), weightKg: 71.9),
        ]
        var goal = self.goal
        goal.startWeightKg = nil
        let suggestion = try suggested(suggest(points: points, goal: goal))
        #expect(isApproximately(suggestion.plannedWeightKg, 70.8))
    }

    // MARK: - 提案しない

    @Test("貯金が 0.5 kg 未満なら提案しない")
    func notAheadEnough() {
        guard case .notSuggested(.notAheadEnough(let aheadKg)) = suggest(forecast: forecast(currentKg: 70.4)) else {
            Issue.record("notAheadEnough のはず")
            return
        }
        #expect(isApproximately(aheadKg, 0.4, tolerance: 1e-9))
    }

    @Test("増量・キープの目標では提案しない")
    func notLosingGoal() {
        let gain = CheatDayGoal(targetWeightKg: 65, deadline: day(70), startDate: day(-30), startWeightKg: 60)
        #expect(suggest(goal: gain) == .notSuggested(.notLosingGoal))
        let keep = CheatDayGoal(targetWeightKg: 60, deadline: day(70), startDate: day(-30), startWeightKg: 60.05)
        #expect(suggest(goal: keep) == .notSuggested(.notLosingGoal))
    }

    @Test("もう目標に届いていれば提案しない")
    func goalReached() {
        #expect(suggest(forecast: forecast(currentKg: 68.05)) == .notSuggested(.goalReached))
    }

    @Test("直近 21 日の記録が 7 日未満なら提案しない（予測の精度が低め）")
    func tooFewRecords() {
        #expect(suggest(forecast: forecast(recordedDays: 6)) == .notSuggested(.tooFewRecords(recordedDays: 6)))
        // 7 日あれば提案する
        #expect(suggest(forecast: forecast(recordedDays: 7)).suggestion != nil)
    }

    @Test("このペースで期限に間に合わない・期限を過ぎたときは提案しない")
    func notOnTrack() {
        #expect(suggest(forecast: forecast(deadlineStatus: .behind(requiredWeeklyChangeKg: -0.8))) == .notSuggested(.notOnTrack))
        #expect(suggest(forecast: forecast(deadlineStatus: .passed)) == .notSuggested(.notOnTrack))
        #expect(suggest(forecast: forecast(deadlineStatus: nil)) == .notSuggested(.notOnTrack))
    }

    @Test("目安がすでに維持カロリーなら、チートデーにしても差がないので提案しない")
    func noDifference() {
        let same = IntakeRecommendation(tdeeKcal: 2000, targetKcal: 2000, dailyBalanceKcal: 0, isRaisedToMinimum: false)
        #expect(suggest(intake: same) == .notSuggested(.noDifference))
    }

    @Test("開始の体重も記録もなければ提案しない")
    func missingStartWeight() {
        var goal = self.goal
        goal.startWeightKg = nil
        #expect(suggest(goal: goal) == .notSuggested(.missingStartWeight))
    }

    // MARK: - すでに決めたチートデー

    @Test("これから 7 日に 1 日決めてあれば、あと 1 日。その日は選べない")
    func oneUpcoming() throws {
        let suggestion = try suggested(suggest(cheatDays: [TestCalendar.day(2, hour: 9)]))
        #expect(suggestion.suggestedDays == 1)
        #expect(suggestion.selectableDates == [0, 1, 3, 4, 5, 6].map { day($0) })
    }

    @Test("これから 7 日に 2 日決めてあれば、週 2 日までなので提案しない")
    func weeklyLimitReached() {
        #expect(suggest(cheatDays: [day(1), day(3)]) == .notSuggested(.weeklyLimitReached))
    }

    @Test("決めた日の分は貯金から先に引く（0.55 kg − 1 日分 0.07 kg は 0.5 kg 未満）")
    func upcomingUsesSavings() {
        let result = suggest(forecast: forecast(currentKg: 70.25), cheatDays: [day(1)])
        guard case .notSuggested(.notAheadEnough(let aheadKg)) = result else {
            Issue.record("notAheadEnough のはず: \(result)")
            return
        }
        #expect(isApproximately(aheadKg, 0.55 - 500.0 / 7200.0, tolerance: 1e-9))
    }

    @Test("過去のチートデーは体重に表れているので貯金からは引かないが、「どの 7 日間でも 2 日まで」には数える")
    func pastCheatDays() throws {
        let suggestion = try suggested(suggest(cheatDays: [day(-6), day(-2)]))
        #expect(isApproximately(suggestion.aheadKg, 0.8))
        #expect(suggestion.suggestedDays == 2)
        // 今日を入れると 6 日前〜今日の 7 日間で 3 日になるので、今日だけ選べない
        #expect(suggestion.selectableDates == (1..<7).map { day($0) })
    }

    @Test("どの 7 日間でも 2 日まで")
    func canAdd() {
        let existing: Set<Date> = [day(0), day(3)]
        #expect(!CheatDaySuggestionAdvisor.canAdd(day(5), to: existing, calendar: calendar))
        #expect(!CheatDaySuggestionAdvisor.canAdd(day(-3), to: existing, calendar: calendar))
        // 3 日の 7 日後（10 日）なら、0 日・3 日のどちらとも同じ 7 日間に 2 日以上は入らない
        #expect(CheatDaySuggestionAdvisor.canAdd(day(10), to: existing, calendar: calendar))
        #expect(CheatDaySuggestionAdvisor.canAdd(day(9), to: [day(3)], calendar: calendar))
    }

    // MARK: - 予定の線

    @Test("予定の線：開始日より前は開始の体重、期限より後は目標体重")
    func plannedWeight() {
        func planned(_ n: Int) -> Double {
            CheatDaySuggestionAdvisor.plannedWeight(
                startKg: 72, targetKg: 68, startDate: day(0), deadline: day(100), on: day(n), calendar: calendar
            )
        }
        #expect(planned(-5) == 72)
        #expect(planned(0) == 72)
        #expect(isApproximately(planned(50), 70))
        #expect(planned(100) == 68)
        #expect(planned(130) == 68)
        // 期限が開始日と同じ（全体 0 日）なら目標体重
        #expect(CheatDaySuggestionAdvisor.plannedWeight(
            startKg: 72, targetKg: 68, startDate: day(0), deadline: day(0), on: day(0), calendar: calendar
        ) == 68)
    }

    @Test("今日がチートデーか（時刻は無視する）")
    func isCheatDay() {
        #expect(CheatDaySuggestionAdvisor.isCheatDay(now, cheatDays: [day(0)], calendar: calendar))
        #expect(!CheatDaySuggestionAdvisor.isCheatDay(now, cheatDays: [day(1), day(-1)], calendar: calendar))
    }
}
