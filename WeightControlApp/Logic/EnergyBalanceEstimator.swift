import Foundation

/// 体重の動きから逆算した、実際のカロリー収支の推定。
nonisolated struct EnergyBalanceEstimate: Equatable, Sendable {
    /// 実際の 1 日の収支（kcal/日）。プラスなら食べた量の方が多い。
    var actualDailyBalanceKcal: Double
    /// 計画の 1 日の収支（kcal/日）
    var plannedDailyBalanceKcal: Double
    /// 計画との差（kcal/日）＝ 実際 − 計画。プラスなら「計画より 1 日あたりこれだけ多く食べている」目安。
    /// 食べ物ベースのヒント（「おにぎり 1 個分」など）に使えます。
    var overPlanKcalPerDay: Double
    /// 推定の 1 日の摂取カロリー（kcal/日）＝ TDEE ＋ 実際の収支。TDEE が分からなければ `nil`。
    var estimatedIntakeKcal: Double?
}

/// トレンドの変化（kg/週）から、「実際には 1 日どれくらいカロリーが多かった／少なかったか」を推定します。
///
/// 体脂肪 1 kg ≈ 7,200 kcal の目安を逆向きに使います。
/// 例：1 週間で 0.35 kg 増えていたら、0.35 × 7,200 ÷ 7 ≈ 1 日 +360 kcal。
///
/// 体重には水分の増減も含まれるので、数日分ではなく 2 週間以上のトレンドで使うのがおすすめです。
nonisolated enum EnergyBalanceEstimator {
    static func estimate(
        observedWeeklyChangeKg: Double,
        plannedWeeklyChangeKg: Double,
        tdeeKcal: Double? = nil
    ) -> EnergyBalanceEstimate {
        let actual = CalorieCalculator.dailyEnergyBalance(forWeeklyChangeKg: observedWeeklyChangeKg)
        let planned = CalorieCalculator.dailyEnergyBalance(forWeeklyChangeKg: plannedWeeklyChangeKg)
        return EnergyBalanceEstimate(
            actualDailyBalanceKcal: actual,
            plannedDailyBalanceKcal: planned,
            overPlanKcalPerDay: actual - planned,
            estimatedIntakeKcal: tdeeKcal.map { $0 + actual }
        )
    }
}
