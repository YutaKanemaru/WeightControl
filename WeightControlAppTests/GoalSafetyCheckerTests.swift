import Foundation
import Testing
@testable import WeightControlApp

/// 目標の安全チェックと修正提案（GoalSafetyChecker）、BMI（BodyMetrics）のテスト
struct GoalSafetyCheckerTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    private func check(current: Double, goal: Double, deadlineDay: Int) -> GoalSafetyResult {
        GoalSafetyChecker.check(
            currentWeightKg: current,
            goalWeightKg: goal,
            deadline: day(deadlineDay),
            now: day(0),
            calendar: calendar
        )
    }

    @Test("8 週間で 2 kg（−0.25 kg/週）は無理のないペース")
    func safeLoss() {
        let result = check(current: 70, goal: 68, deadlineDay: 56)
        guard case .safe(let required) = result else {
            Issue.record("安全と判定されていない: \(result)")
            return
        }
        #expect(isApproximately(required, -0.25))
        #expect(isApproximately(result.plannedWeeklyChangeKg, -0.25))
    }

    @Test("ちょうど体重の 1 %/週（70 kg で −0.7 kg/週）は無理のない範囲")
    func exactlyAtLimit() {
        // 10 週間（70 日）で 7 kg
        guard case .safe = check(current: 70, goal: 63, deadlineDay: 70) else {
            Issue.record("上限ちょうどが安全と判定されていない")
            return
        }
    }

    @Test("4 週間で 10 kg は速すぎる → 期限と目標体重の修正案を出す")
    func tooAggressiveLoss() throws {
        let result = check(current: 70, goal: 60, deadlineDay: 28)
        guard case .tooAggressive(let correction) = result else {
            Issue.record("速すぎると判定されていない: \(result)")
            return
        }
        #expect(isApproximately(correction.requiredWeeklyChangeKg ?? 0, -2.5))
        #expect(isApproximately(correction.maxWeeklyChangeKg, -0.7))
        // 10 kg ÷ 0.7 kg/週 ≈ 14.3 週 = 100 日
        #expect(correction.suggestedDeadline == day(100))
        // 4 週間で −2.8 kg → 67.2 kg
        #expect(correction.suggestedGoalWeightKg == 67.2)
        // カロリー計算には上限のペースを使う
        #expect(isApproximately(result.plannedWeeklyChangeKg, -0.7))
    }

    @Test("提案する目標体重は、今の体重に近い側に 0.1 kg 単位で丸める")
    func suggestedGoalRoundsTowardCurrent() {
        // 73 kg、3 週間 → 上限 −0.73 kg/週 × 3 = −2.19 kg → 70.81 → 70.9 kg
        guard case .tooAggressive(let correction) = check(current: 73, goal: 60, deadlineDay: 21) else {
            Issue.record("速すぎると判定されていない")
            return
        }
        #expect(correction.suggestedGoalWeightKg == 70.9)
    }

    @Test("増量は体重の 0.5 %/週まで")
    func tooAggressiveGain() {
        // 50 kg → 上限 +0.25 kg/週。4 週間で 5 kg は速すぎる
        guard case .tooAggressive(let correction) = check(current: 50, goal: 55, deadlineDay: 28) else {
            Issue.record("速すぎると判定されていない")
            return
        }
        #expect(isApproximately(correction.maxWeeklyChangeKg, 0.25))
        // 5 kg ÷ 0.25 kg/週 = 20 週 = 140 日
        #expect(correction.suggestedDeadline == day(140))
        // 4 週間で +1.0 kg → 51.0 kg
        #expect(correction.suggestedGoalWeightKg == 51.0)
    }

    @Test("増量でも無理のないペースなら安全")
    func safeGain() {
        guard case .safe(let required) = check(current: 50, goal: 51, deadlineDay: 56) else {
            Issue.record("安全と判定されていない")
            return
        }
        #expect(isApproximately(required, 0.125))
    }

    @Test("期限が今日以前なら、目標体重はそのままで期限だけ提案する")
    func deadlinePassed() {
        guard case .tooAggressive(let correction) = check(current: 70, goal: 68, deadlineDay: 0) else {
            Issue.record("速すぎると判定されていない")
            return
        }
        #expect(correction.requiredWeeklyChangeKg == nil)
        #expect(correction.suggestedGoalWeightKg == nil)
        // 2 kg ÷ 0.7 kg/週 ≈ 2.86 週 = 20 日
        #expect(correction.suggestedDeadline == day(20))
    }

    @Test("もう目標体重なら「届いている」")
    func alreadyAtGoal() {
        let result = check(current: 65.05, goal: 65, deadlineDay: 30)
        #expect(result == .alreadyAtGoal)
        #expect(result.plannedWeeklyChangeKg == 0)
    }

    // MARK: - BMI

    @Test("BMI ＝ 体重 ÷ 身長(m)²")
    func bmi() {
        #expect(isApproximately(BodyMetrics.bmi(weightKg: 64, heightCm: 160), 25))
        #expect(BodyMetrics.bmi(weightKg: 64, heightCm: 0) == 0)
    }

    @Test("目標体重の BMI が 18.5 未満かどうか")
    func lowBMIGoal() {
        // 160 cm で BMI 18.5 は 47.36 kg
        #expect(BodyMetrics.isBelowLowerNormalBMI(weightKg: 47, heightCm: 160))
        #expect(BodyMetrics.isBelowLowerNormalBMI(weightKg: 48, heightCm: 160) == false)
    }
}
