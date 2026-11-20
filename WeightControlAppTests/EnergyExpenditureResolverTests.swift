import Foundation
import Testing
@testable import WeightControlApp

/// 消費カロリーの計算方法の切り替え（EnergyExpenditureResolver）のテスト
struct EnergyExpenditureResolverTests {
    private func summary(days: Int = 14, activeEnergyKcal: Double = 400) -> ActivitySummary {
        ActivitySummary(
            dayCount: days,
            averageSteps: 8000,
            averageActiveEnergyKcal: activeEnergyKcal,
            averageActiveMinutes: 30,
            suggestedLevel: .moderate
        )
    }

    // MARK: - 自動

    @Test("自動：ヘルスケアの実績が 7 日分以上あれば実績を使う")
    func automaticUsesHealth() {
        let choice = EnergyExpenditureResolver.choose(mode: .automatic, activityLevel: .light, healthActivity: summary(days: 7))
        #expect(choice == EnergyExpenditureChoice(source: .healthKit(averageActiveEnergyKcal: 400, days: 7), isFallback: false))
    }

    @Test("自動：ヘルスケアのデータがなければ活動量を使う（代わりではないので isFallback は false）")
    func automaticWithoutHealth() {
        let choice = EnergyExpenditureResolver.choose(mode: .automatic, activityLevel: .light, healthActivity: nil)
        #expect(choice == EnergyExpenditureChoice(source: .activityLevel(.light), isFallback: false))
    }

    @Test("自動：アクティブエネルギーが 0（カロリーが読めない）なら活動量を使う")
    func automaticWithZeroEnergy() {
        let choice = EnergyExpenditureResolver.choose(mode: .automatic, activityLevel: .sedentary, healthActivity: summary(activeEnergyKcal: 0))
        #expect(choice.source == .activityLevel(.sedentary))
    }

    @Test("6 日分しかなければ使えない")
    func notEnoughDays() {
        #expect(!EnergyExpenditureResolver.isUsable(summary(days: 6)))
        #expect(EnergyExpenditureResolver.isUsable(summary(days: 7)))
    }

    // MARK: - 手動

    @Test("活動量を選んでいれば、ヘルスケアのデータがあっても活動量を使う")
    func activityLevelMode() {
        let choice = EnergyExpenditureResolver.choose(mode: .activityLevel, activityLevel: .active, healthActivity: summary())
        #expect(choice == EnergyExpenditureChoice(source: .activityLevel(.active), isFallback: false))
    }

    @Test("ヘルスケアの実績を選んでいて、データがあれば実績を使う")
    func healthKitMode() {
        let choice = EnergyExpenditureResolver.choose(mode: .healthKit, activityLevel: .light, healthActivity: summary(days: 20, activeEnergyKcal: 350))
        #expect(choice == EnergyExpenditureChoice(source: .healthKit(averageActiveEnergyKcal: 350, days: 20), isFallback: false))
    }

    @Test("ヘルスケアの実績を選んでいても、データが足りなければ活動量で計算し、そのことを知らせる")
    func healthKitModeFallsBack() {
        let choice = EnergyExpenditureResolver.choose(mode: .healthKit, activityLevel: .light, healthActivity: nil)
        #expect(choice == EnergyExpenditureChoice(source: .activityLevel(.light), isFallback: true))
    }

    // MARK: - TDEE

    @Test("活動量なら 基礎代謝 × 活動係数")
    func tdeeFromActivityLevel() {
        let tdee = EnergyExpenditureResolver.totalDailyEnergyExpenditure(bmrKcal: 1600, source: .activityLevel(.light))
        #expect(isApproximately(tdee, 2200))
    }

    @Test("実績なら（基礎代謝 ＋ アクティブエネルギー）÷ 0.9")
    func tdeeFromHealth() {
        let tdee = EnergyExpenditureResolver.totalDailyEnergyExpenditure(
            bmrKcal: 1600,
            source: .healthKit(averageActiveEnergyKcal: 380, days: 14)
        )
        #expect(isApproximately(tdee, 2200))
    }
}
