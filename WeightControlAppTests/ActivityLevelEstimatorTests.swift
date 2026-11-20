import Foundation
import Testing
@testable import WeightControlApp

/// ヘルスケアの実績から活動量の目安を出す（ActivityLevelEstimator）のテスト
struct ActivityLevelEstimatorTests {

    private func days(_ count: Int, steps: Double = 0, minutes: Double = 0, energy: Double = 0) -> [DailyActivity] {
        (0..<count).map {
            DailyActivity(day: TestCalendar.day($0), exerciseMinutes: minutes, activeEnergyKcal: energy, steps: steps)
        }
    }

    @Test("データのある日が 7 日未満なら目安を出さない")
    func needsSevenDays() {
        #expect(ActivityLevelEstimator.summarize(days(6, steps: 8_000)) == nil)
        #expect(ActivityLevelEstimator.summarize(days(7, steps: 8_000)) != nil)
    }

    @Test("データがない日（スマホを置きっぱなしの日など）は平均に入れない")
    func ignoresEmptyDays() throws {
        let summary = try #require(ActivityLevelEstimator.summarize(days(7, steps: 6_000) + days(5)))
        #expect(summary.dayCount == 7)
        #expect(summary.averageSteps == 6_000)
    }

    @Test("平均歩数から活動量の段階を決める", arguments: [
        (3_000.0, ActivityLevel.sedentary),
        (5_000, .light),
        (7_500, .moderate),
        (10_000, .active),
        (12_500, .veryActive),
    ])
    func levelFromSteps(steps: Double, expected: ActivityLevel) throws {
        let summary = try #require(ActivityLevelEstimator.summarize(days(7, steps: steps)))
        #expect(summary.suggestedLevel == expected)
    }

    @Test("歩数が少なくても、運動時間が多ければ高い方の段階にする")
    func usesHigherOfStepsAndMinutes() throws {
        // 1 日 25 分 × 7 日 = 週 175 分 → moderate（歩数だけなら sedentary）
        let summary = try #require(ActivityLevelEstimator.summarize(days(7, steps: 2_000, minutes: 25)))
        #expect(summary.suggestedLevel == .moderate)
    }

    @Test("平均のアクティブエネルギーを出す")
    func averagesEnergy() throws {
        let summary = try #require(ActivityLevelEstimator.summarize(days(4, steps: 1, energy: 200) + days(4, steps: 1, energy: 400)))
        #expect(isApproximately(summary.averageActiveEnergyKcal, 300))
    }
}
