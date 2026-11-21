import Foundation
import Testing
@testable import WeightControlApp

/// 目標の期限の提案（GoalDeadlineProposer）のテスト。数字は docs/GOAL_DEADLINE.md の例に合わせています。
struct GoalDeadlineProposerTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    private func propose(
        current: Double,
        target: Double,
        mode: GoalPaceMode,
        energy: DeadlineEnergy? = nil
    ) -> GoalDeadlineProposal {
        GoalDeadlineProposer.propose(
            currentWeightKg: current,
            targetWeightKg: target,
            mode: mode,
            energy: energy,
            now: day(0),
            calendar: calendar
        )
    }

    private func suggestion(_ proposal: GoalDeadlineProposal) -> GoalDeadlineSuggestion? {
        if case .proposed(let suggestion) = proposal { return suggestion }
        Issue.record("提案されていない: \(proposal)")
        return nil
    }

    // MARK: - モードの割合

    @Test("ハードは安全チェックの上限そのまま、ゆるやかはその半分、自分で決めるは割合なし")
    func ratios() {
        #expect(GoalPaceMode.hard.weeklyRatio(isLosing: true) == GoalSafetyChecker.maxWeeklyLossRatio)
        #expect(GoalPaceMode.hard.weeklyRatio(isLosing: false) == GoalSafetyChecker.maxWeeklyGainRatio)
        #expect(GoalPaceMode.gentle.weeklyRatio(isLosing: true) == GoalSafetyChecker.maxWeeklyLossRatio / 2)
        #expect(GoalPaceMode.gentle.weeklyRatio(isLosing: false) == GoalSafetyChecker.maxWeeklyGainRatio / 2)
        #expect(GoalPaceMode.manual.weeklyRatio(isLosing: true) == nil)
    }

    // MARK: - 減量

    @Test("70 kg から 5 kg 減らす：ゆるやかは週 0.35 kg で 100 日")
    func gentleLoss() throws {
        let result = try #require(suggestion(propose(current: 70, target: 65, mode: .gentle)))
        #expect(result.days == 100)
        #expect(result.deadline == day(100))
        #expect(isApproximately(result.weeklyChangeKg, -0.35))
        #expect(!result.isLimitedByIntakeFloor)
        #expect(!result.isBeyondHorizon)
    }

    @Test("70 kg から 5 kg 減らす：ハードは週 0.7 kg で 50 日")
    func hardLoss() throws {
        let result = try #require(suggestion(propose(current: 70, target: 65, mode: .hard)))
        #expect(result.days == 50)
        #expect(result.deadline == day(50))
        #expect(isApproximately(result.weeklyChangeKg, -0.7))
    }

    @Test("ハードの提案は、安全チェックで「無理のないペース」になる")
    func hardIsSafe() throws {
        let result = try #require(suggestion(propose(current: 68.3, target: 61.7, mode: .hard)))
        let safety = GoalSafetyChecker.check(
            currentWeightKg: 68.3,
            goalWeightKg: 61.7,
            deadline: result.deadline,
            now: day(0),
            calendar: calendar
        )
        guard case .safe = safety else {
            Issue.record("安全と判定されていない: \(safety)")
            return
        }
    }

    @Test("日数は切り上げる（1.1 kg ÷ 週 0.35 kg = 22 日）")
    func roundsUp() throws {
        // 1.1 ÷ 0.35 × 7 = 22.0、1.2 ÷ 0.35 × 7 = 24.0、1.15 ÷ 0.35 × 7 = 23.0…
        let result = try #require(suggestion(propose(current: 70, target: 68.9, mode: .gentle)))
        #expect(result.days == 22)
        let longer = try #require(suggestion(propose(current: 70, target: 68.8, mode: .gentle)))
        // 1.2 ÷ 0.35 × 7 = 24
        #expect(longer.days == 24)
        let between = try #require(suggestion(propose(current: 70, target: 68.85, mode: .gentle)))
        // 1.15 ÷ 0.35 × 7 = 23
        #expect(between.days == 23)
    }

    @Test("「自分で決める」を渡したときは、ゆるやかとして計算する")
    func manualFallsBackToGentle() {
        #expect(propose(current: 70, target: 65, mode: .manual) == propose(current: 70, target: 65, mode: .gentle))
    }

    // MARK: - 増量

    @Test("60 kg から 2 kg 増やす：ゆるやかは週 0.15 kg で 94 日、ハードは週 0.3 kg で 47 日")
    func gain() throws {
        let gentle = try #require(suggestion(propose(current: 60, target: 62, mode: .gentle)))
        #expect(isApproximately(gentle.weeklyChangeKg, 0.15))
        #expect(gentle.days == 94) // 2 ÷ 0.15 × 7 = 93.3… → 94
        let hard = try #require(suggestion(propose(current: 60, target: 62, mode: .hard)))
        #expect(isApproximately(hard.weeklyChangeKg, 0.3))
        #expect(hard.days == 47) // 2 ÷ 0.3 × 7 = 46.6… → 47
    }

    @Test("増やすときは、食事の下限で止めない")
    func gainIgnoresIntakeFloor() throws {
        let energy = DeadlineEnergy(tdeeKcal: 1200, minimumIntakeKcal: 1200)
        let result = try #require(suggestion(propose(current: 60, target: 62, mode: .gentle, energy: energy)))
        #expect(!result.isLimitedByIntakeFloor)
        #expect(result.days == 94)
    }

    // MARK: - もう届いている

    @Test("差が 0.1 kg 以下なら期限を出さない")
    func alreadyAtGoal() {
        #expect(propose(current: 70, target: 69.95, mode: .gentle) == .alreadyAtGoal)
        #expect(propose(current: 70, target: 70.1, mode: .hard) == .alreadyAtGoal)
        #expect(propose(current: 70, target: 70, mode: .hard).deadline == nil)
    }

    // MARK: - 食事の下限

    @Test("食事の下限で出せるペース：（消費 − 下限）× 7 ÷ 7200")
    func floorPace() {
        let energy = DeadlineEnergy(tdeeKcal: 2000, minimumIntakeKcal: 1500)
        #expect(isApproximately(GoalDeadlineProposer.maxWeeklyLossKgByIntakeFloor(energy), 500.0 * 7 / 7200))
        let none = DeadlineEnergy(tdeeKcal: 1100, minimumIntakeKcal: 1200)
        #expect(GoalDeadlineProposer.maxWeeklyLossKgByIntakeFloor(none) == 0)
    }

    @Test("仕様の例：女性・55 kg・160 cm・40 歳・活動量「低い」は、どちらのモードも週 0.22 kg で同じ期限")
    func floorLimitsBothModes() throws {
        let profile = DashboardProfile(
            heightCm: 160,
            birthYear: 1987, // 基準日は 2027 年なので 40 歳
            sex: .female,
            activityLevel: .sedentary,
            energyMode: .activityLevel
        )
        let energy = GoalDeadlineProposer.energy(
            profile: profile,
            weightKg: 55,
            healthActivity: nil,
            now: day(0),
            calendar: calendar
        )
        // 基礎代謝 1,189 kcal、消費 1,189 × 1.2 = 1,426.8 kcal、下限 1,200 kcal
        #expect(isApproximately(energy.tdeeKcal, 1426.8, tolerance: 1e-6))
        #expect(isApproximately(energy.minimumIntakeKcal, 1200))

        let gentle = try #require(suggestion(propose(current: 55, target: 50, mode: .gentle, energy: energy)))
        let hard = try #require(suggestion(propose(current: 55, target: 50, mode: .hard, energy: energy)))
        // 226.8 × 7 ÷ 7200 = 0.2205 kg/週 → 5 ÷ 0.2205 × 7 = 158.7… → 159 日
        #expect(isApproximately(gentle.weeklyChangeKg, -0.2205, tolerance: 1e-9))
        #expect(gentle.days == 159)
        #expect(hard.days == 159)
        #expect(gentle.isLimitedByIntakeFloor && hard.isLimitedByIntakeFloor)
        #expect(gentle.isSameForAllModes && hard.isSameForAllModes)
    }

    @Test("ハードだけが食事の下限で止まるときは、ゆるやかとは別の期限になる")
    func floorLimitsOnlyHard() throws {
        // 消費 2,000・下限 1,500 → 週 0.486 kg まで。ゆるやか 0.35 kg は届く、ハード 0.7 kg は止まる
        let energy = DeadlineEnergy(tdeeKcal: 2000, minimumIntakeKcal: 1500)
        let gentle = try #require(suggestion(propose(current: 70, target: 65, mode: .gentle, energy: energy)))
        #expect(gentle.days == 100)
        #expect(!gentle.isLimitedByIntakeFloor)
        #expect(!gentle.isSameForAllModes)

        let hard = try #require(suggestion(propose(current: 70, target: 65, mode: .hard, energy: energy)))
        #expect(hard.days == 72) // 5 ÷ (3500 ÷ 7200) × 7 = 72
        #expect(hard.isLimitedByIntakeFloor)
        #expect(!hard.isSameForAllModes)
    }

    @Test("消費カロリーが下限とほぼ同じなら、食事だけでは減らしにくいと返す")
    func notReachableByDiet() {
        let energy = DeadlineEnergy(tdeeKcal: 1200, minimumIntakeKcal: 1200)
        #expect(propose(current: 50, target: 48, mode: .gentle, energy: energy) == .notReachableByDiet)
        #expect(propose(current: 50, target: 48, mode: .hard, energy: energy).deadline == nil)
    }

    // MARK: - 2 年より先

    @Test("期限が 730 日より先なら「手前の目標から」の印を付ける")
    func beyondHorizon() throws {
        // 150 kg から 60 kg：ゆるやか週 0.75 kg → 90 ÷ 0.75 × 7 = 840 日
        let far = try #require(suggestion(propose(current: 150, target: 60, mode: .gentle)))
        #expect(far.days == 840)
        #expect(far.isBeyondHorizon)
        // ハードなら 420 日で 2 年以内
        let hard = try #require(suggestion(propose(current: 150, target: 60, mode: .hard)))
        #expect(hard.days == 420)
        #expect(!hard.isBeyondHorizon)
    }

    // MARK: - 期間の言い方

    @Test("期間の言い方：2 週間未満は日、2 か月未満は週、1 年未満は半月きざみ、それ以上は年と月")
    func duration() {
        #expect(GoalDeadlineProposer.duration(days: 5) == .days(5))
        #expect(GoalDeadlineProposer.duration(days: 13) == .days(13))
        #expect(GoalDeadlineProposer.duration(days: 14) == .weeks(2))
        #expect(GoalDeadlineProposer.duration(days: 50) == .weeks(7))
        #expect(GoalDeadlineProposer.duration(days: 60) == .months(1, half: true))
        #expect(GoalDeadlineProposer.duration(days: 100) == .months(3, half: false))
        #expect(GoalDeadlineProposer.duration(days: 159) == .months(5, half: false))
        #expect(GoalDeadlineProposer.duration(days: 400) == .years(1, months: 1))
        #expect(GoalDeadlineProposer.duration(days: 840) == .years(2, months: 3))
    }
}
