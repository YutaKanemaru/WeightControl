import Foundation
import Testing
@testable import WeightControlApp

/// 目標の入力画面に出すひとこと（GoalPlanAdvisor）のテスト
struct GoalPlanAdvisorTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    private func advice(target: Double?, current: Double?, deadlineDay: Int) -> GoalPlanAdvice {
        GoalPlanAdvisor.advice(
            targetWeightKg: target,
            currentWeightKg: current,
            deadline: day(deadlineDay),
            now: day(0),
            calendar: calendar
        )
    }

    @Test("目標体重が入っていなければ、判定せずに入力を待つ")
    func needsTarget() {
        #expect(advice(target: nil, current: 70, deadlineDay: 56) == .needsTargetWeight)
        // 今の体重もないときも、まずは目標体重を求める
        #expect(advice(target: nil, current: nil, deadlineDay: 56) == .needsTargetWeight)
    }

    @Test("体重の記録がなければ、ペースは判定できない")
    func needsCurrentWeight() {
        #expect(advice(target: 65, current: nil, deadlineDay: 56) == .needsCurrentWeight)
    }

    @Test("今の体重がほぼ目標なら「もう届いている」")
    func alreadyAtGoal() {
        #expect(advice(target: 70, current: 70.05, deadlineDay: 56) == .alreadyAtGoal)
    }

    @Test("8 週間で 2 kg は無理のないペース（−0.25 kg/週・残り 56 日）")
    func comfortable() {
        guard case .comfortable(let weekly, let daysLeft) = advice(target: 68, current: 70, deadlineDay: 56) else {
            Issue.record("無理のないペースと判定されていない")
            return
        }
        #expect(isApproximately(weekly, -0.25))
        #expect(daysLeft == 56)
    }

    @Test("4 週間で 10 kg は速すぎる → GoalSafetyChecker と同じ修正案を返す")
    func tooFast() {
        let result = advice(target: 60, current: 70, deadlineDay: 28)
        let expected = GoalSafetyChecker.check(
            currentWeightKg: 70, goalWeightKg: 60, deadline: day(28), now: day(0), calendar: calendar
        )
        guard case .tooFast(let correction) = result, case .tooAggressive(let expectedCorrection) = expected else {
            Issue.record("速すぎると判定されていない: \(result)")
            return
        }
        #expect(correction == expectedCorrection)
    }

    @Test("期限までの日数は、過ぎていれば 0")
    func daysLeftClampsAtZero() {
        #expect(GoalPlanAdvisor.daysLeft(until: day(10), now: day(0), calendar: calendar) == 10)
        #expect(GoalPlanAdvisor.daysLeft(until: TestCalendar.day(0, hour: 23), now: day(0), calendar: calendar) == 0)
        #expect(GoalPlanAdvisor.daysLeft(until: day(-3), now: day(0), calendar: calendar) == 0)
    }
}
