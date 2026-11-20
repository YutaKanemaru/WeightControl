import Foundation
import Testing
@testable import WeightControlApp

/// 計画が出なかったときにテストを止めるためのエラー
private struct PlanNotAvailable: Error {}

/// チートデー計画（CheatDayBudgetPlanner）のテスト
struct CheatDayBudgetPlannerTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    private func plan(
        target: Double = 2000,
        minimum: Double = 1500,
        cheatDays: [Int] = [5],
        desiredExtra: Double? = nil
    ) -> CheatDayPlanResult {
        CheatDayBudgetPlanner.plan(
            dailyTargetKcal: target,
            minimumIntakeKcal: minimum,
            startDate: day(0),
            cheatDates: cheatDays.map { day($0) },
            desiredCheatDayExtraKcal: desiredExtra,
            calendar: calendar
        )
    }

    private func available(_ result: CheatDayPlanResult) throws -> CheatDayPlan {
        guard case .available(let plan) = result else {
            Issue.record("計画が出ていない: \(result)")
            throw PlanNotAvailable()
        }
        return plan
    }

    // MARK: - 基本

    @Test("希望なしなら、ふだんの日は 1 日 300 kcal まで控えめにして、チートデーに回す")
    func maximumSavingByDefault() throws {
        // 目安 2000、下限 1500 → 控えめにできるのは min(500, 300) = 300 kcal/日
        // ふだんの日 6 日 × 300 = 1800 kcal をチートデー 1 日に回す → 3800 kcal
        let result = try available(plan())
        #expect(result.weeklyBudgetKcal == 14_000)
        #expect(result.dailySavingKcal == 300)
        #expect(result.regularDayKcal == 1700)
        #expect(result.cheatDayExtraKcal == 1800)
        #expect(result.cheatDayKcal == 3800)
        #expect(result.isLimited == false)
    }

    @Test("チートデーに 600 kcal 多く食べたいなら、ふだんの日は 100 kcal ずつ控えめに")
    func desiredExtra() throws {
        let result = try available(plan(desiredExtra: 600))
        #expect(result.dailySavingKcal == 100)
        #expect(result.regularDayKcal == 1900)
        #expect(result.cheatDayKcal == 2600)
        #expect(result.isLimited == false)
    }

    @Test("割り切れない希望でも、1 週間の合計は予算どおり")
    func unevenDesiredExtra() throws {
        // 500 ÷ 6 ≈ 83.3 kcal/日
        let result = try available(plan(desiredExtra: 500))
        #expect(isApproximately(result.dailySavingKcal, 500.0 / 6))
        #expect(isApproximately(result.cheatDayKcal, 2500))
        #expect(isApproximately(result.days.reduce(0) { $0 + $1.intakeKcal }, result.weeklyBudgetKcal, tolerance: 1e-6))
    }

    @Test("チートデーが 2 日なら、貯めた分を 2 日で分ける")
    func twoCheatDays() throws {
        // ふだんの日 5 日 × 300 = 1500 kcal を 2 日で分ける → 1 日 750 kcal 多め
        let result = try available(plan(cheatDays: [2, 5]))
        #expect(result.regularDayKcal == 1700)
        #expect(result.cheatDayExtraKcal == 750)
        #expect(result.cheatDayKcal == 2750)
        #expect(result.days.filter(\.isCheatDay).map(\.date) == [day(2), day(5)])
    }

    // MARK: - 下限を守る

    @Test("下限（基礎代謝など）を下回らないよう、控えめにする量を抑える")
    func neverBelowMinimum() throws {
        // 目安 1600、下限 1500 → 控えめにできるのは 100 kcal/日まで
        // 1200 kcal 多く食べたい（必要なのは 200 kcal/日）が、100 kcal/日 × 6 = 600 kcal まで
        let result = try available(plan(target: 1600, minimum: 1500, desiredExtra: 1200))
        #expect(result.dailySavingKcal == 100)
        #expect(result.regularDayKcal == 1500)
        #expect(result.cheatDayExtraKcal == 600)
        #expect(result.isLimited)
        #expect(result.days.allSatisfy { $0.intakeKcal >= 1500 })
    }

    @Test("目安がもう下限ちょうどなら、貯められない（チートデーも目安どおり）")
    func targetAtMinimum() throws {
        let result = try available(plan(target: 1500, minimum: 1500))
        #expect(result.dailySavingKcal == 0)
        #expect(result.regularDayKcal == 1500)
        #expect(result.cheatDayKcal == 1500)
        #expect(result.isLimited)
    }

    @Test("目安が下限より低く渡されても、さらに減らすことはしない")
    func targetBelowMinimum() throws {
        let result = try available(plan(target: 1400, minimum: 1500))
        #expect(result.dailySavingKcal == 0)
        #expect(result.regularDayKcal == 1400)
    }

    @Test("1 日に控えめにする量は 300 kcal まで（大きな希望でも）")
    func savingIsCapped() throws {
        let result = try available(plan(target: 2500, minimum: 1500, desiredExtra: 3000))
        #expect(result.dailySavingKcal == 300)
        #expect(result.cheatDayExtraKcal == 1800)
        #expect(result.isLimited)
    }

    @Test("マイナスの希望は 0 とみなす")
    func negativeDesiredExtra() throws {
        let result = try available(plan(desiredExtra: -200))
        #expect(result.dailySavingKcal == 0)
        #expect(result.cheatDayKcal == 2000)
        #expect(result.isLimited == false)
    }

    // MARK: - 日付

    @Test("7 日分の予定が、1 日目から順に並び、チートデーの日に印がつく")
    func daysAreListedInOrder() throws {
        let result = try available(plan(cheatDays: [5]))
        #expect(result.days.map(\.date) == (0..<7).map { day($0) })
        #expect(result.days.map(\.isCheatDay) == [false, false, false, false, false, true, false])
        #expect(result.days.reduce(0) { $0 + $1.intakeKcal } == result.weeklyBudgetKcal)
    }

    @Test("チートデーの日付に時刻がついていても、その日として扱う")
    func cheatDateWithTime() throws {
        let result = CheatDayBudgetPlanner.plan(
            dailyTargetKcal: 2000, minimumIntakeKcal: 1500,
            startDate: day(0), cheatDates: [TestCalendar.day(3, hour: 19)], calendar: calendar
        )
        #expect(try available(result).days[3].isCheatDay)
    }

    @Test("同じ日を 2 回選んでも 1 日と数える")
    func duplicateCheatDates() throws {
        let result = try available(plan(cheatDays: [5, 5]))
        #expect(result.days.filter(\.isCheatDay).count == 1)
        #expect(result.cheatDayKcal == 3800)
    }

    // MARK: - 立てられないとき

    @Test("チートデーがない・7 日の外だけ・3 日以上なら、計画を立てない")
    func invalidCheatDayCount() {
        #expect(plan(cheatDays: []) == .invalidCheatDayCount(0))
        #expect(plan(cheatDays: [7, -1]) == .invalidCheatDayCount(0))
        #expect(plan(cheatDays: [1, 3, 5]) == .invalidCheatDayCount(3))
    }
}
