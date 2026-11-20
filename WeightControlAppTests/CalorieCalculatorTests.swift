import Foundation
import Testing
@testable import WeightControlApp

/// カロリー計算（CalorieCalculator）と収支の推定（EnergyBalanceEstimator）のテスト
struct CalorieCalculatorTests {

    @Test("基礎代謝（男性 70 kg・175 cm・30 歳）＝ 1,648.75 kcal")
    func bmrMale() {
        // 700 + 1093.75 − 150 + 5
        let bmr = CalorieCalculator.basalMetabolicRate(weightKg: 70, heightCm: 175, ageYears: 30, sex: .male)
        #expect(isApproximately(bmr, 1648.75))
    }

    @Test("基礎代謝（女性 55 kg・160 cm・25 歳）＝ 1,264 kcal")
    func bmrFemale() {
        // 550 + 1000 − 125 − 161
        let bmr = CalorieCalculator.basalMetabolicRate(weightKg: 55, heightCm: 160, ageYears: 25, sex: .female)
        #expect(isApproximately(bmr, 1264))
    }

    @Test("生まれた年から年齢を出す")
    func ageFromBirthYear() {
        let date = TestCalendar.day(0) // 2027-01-15
        #expect(CalorieCalculator.ageYears(birthYear: 1990, on: date, calendar: TestCalendar.utc) == 37)
        #expect(CalorieCalculator.ageYears(birthYear: 2030, on: date, calendar: TestCalendar.utc) == 0)
    }

    @Test("活動係数は活動量が多いほど大きい", arguments: zip(
        [ActivityLevel.sedentary, .light, .moderate, .active, .veryActive],
        [1.2, 1.375, 1.55, 1.725, 1.9]
    ))
    func activityFactors(level: ActivityLevel, factor: Double) {
        #expect(level.factor == factor)
        #expect(isApproximately(CalorieCalculator.totalDailyEnergyExpenditure(bmrKcal: 1000, activityLevel: level), 1000 * factor))
    }

    @Test("運動量（アクティブエネルギー）から TDEE を出す")
    func tdeeFromActiveEnergy() {
        // (1,500 + 300) ÷ 0.9 = 2,000
        let tdee = CalorieCalculator.totalDailyEnergyExpenditure(bmrKcal: 1500, averageActiveEnergyKcal: 300)
        #expect(isApproximately(tdee, 2000))
        // マイナスの運動量は 0 として扱う
        let noActivity = CalorieCalculator.totalDailyEnergyExpenditure(bmrKcal: 1500, averageActiveEnergyKcal: -50)
        #expect(isApproximately(noActivity, 1500 / 0.9))
    }

    @Test("1 週間に 0.5 kg 減らすには、1 日約 514 kcal のマイナス")
    func dailyBalanceForPace() {
        #expect(isApproximately(CalorieCalculator.dailyEnergyBalance(forWeeklyChangeKg: -0.5), -3600.0 / 7))
        #expect(isApproximately(CalorieCalculator.dailyEnergyBalance(forWeeklyChangeKg: 0.7), 720))
        #expect(CalorieCalculator.dailyEnergyBalance(forWeeklyChangeKg: 0) == 0)
    }

    @Test("推奨摂取カロリー ＝ TDEE − 目標ペースに必要な分")
    func recommendedIntake() {
        let plan = CalorieCalculator.recommendedIntake(tdeeKcal: 2000, bmrKcal: 1264, sex: .female, plannedWeeklyChangeKg: -0.5)
        #expect(isApproximately(plan.targetKcal, 2000 - 3600.0 / 7))
        #expect(isApproximately(plan.dailyBalanceKcal, -3600.0 / 7))
        #expect(plan.tdeeKcal == 2000)
        #expect(plan.isRaisedToMinimum == false)
    }

    @Test("推奨摂取カロリーは基礎代謝を下回らない")
    func intakeNotBelowBMR() {
        // 2,000 − 1,028.6 = 971 kcal → 基礎代謝 1,264 kcal に引き上げ
        let plan = CalorieCalculator.recommendedIntake(tdeeKcal: 2000, bmrKcal: 1264, sex: .female, plannedWeeklyChangeKg: -1.0)
        #expect(plan.targetKcal == 1264)
        #expect(isApproximately(plan.dailyBalanceKcal, -736))
        #expect(plan.isRaisedToMinimum)
    }

    @Test("下限は、基礎代謝と性別ごとの目安（男性 1,500・女性 1,200）の大きい方")
    func minimumIntake() {
        #expect(CalorieCalculator.minimumIntakeKcal(bmrKcal: 1100, sex: .female) == 1200)
        #expect(CalorieCalculator.minimumIntakeKcal(bmrKcal: 1300, sex: .male) == 1500)
        #expect(CalorieCalculator.minimumIntakeKcal(bmrKcal: 1700, sex: .male) == 1700)
    }

    @Test("増量のペースなら、TDEE より多く食べる目安になる")
    func intakeForGain() {
        let plan = CalorieCalculator.recommendedIntake(tdeeKcal: 2000, bmrKcal: 1300, sex: .male, plannedWeeklyChangeKg: 0.25)
        #expect(isApproximately(plan.targetKcal, 2000 + 1800.0 / 7))
        #expect(plan.isRaisedToMinimum == false)
    }

    // MARK: - 実際の収支の推定

    @Test("計画は −0.5 kg/週なのに実際は ±0 なら、1 日約 514 kcal 多く食べている")
    func overPlanEstimate() {
        let estimate = EnergyBalanceEstimator.estimate(observedWeeklyChangeKg: 0, plannedWeeklyChangeKg: -0.5, tdeeKcal: 2000)
        #expect(estimate.actualDailyBalanceKcal == 0)
        #expect(isApproximately(estimate.plannedDailyBalanceKcal, -3600.0 / 7))
        #expect(isApproximately(estimate.overPlanKcalPerDay, 3600.0 / 7))
        #expect(estimate.estimatedIntakeKcal == 2000)
    }

    @Test("1 週間で 0.35 kg 増えていたら、1 日 +360 kcal")
    func surplusFromGain() {
        let estimate = EnergyBalanceEstimator.estimate(observedWeeklyChangeKg: 0.35, plannedWeeklyChangeKg: 0)
        #expect(isApproximately(estimate.actualDailyBalanceKcal, 360))
        #expect(isApproximately(estimate.overPlanKcalPerDay, 360))
        #expect(estimate.estimatedIntakeKcal == nil)
    }

    @Test("計画より速く減っていれば、計画との差はマイナス")
    func aheadOfPlan() {
        let estimate = EnergyBalanceEstimator.estimate(observedWeeklyChangeKg: -0.7, plannedWeeklyChangeKg: -0.5, tdeeKcal: 2200)
        #expect(isApproximately(estimate.overPlanKcalPerDay, -1440.0 / 7))
        #expect(isApproximately(estimate.estimatedIntakeKcal ?? 0, 2200 - 720))
    }
}
