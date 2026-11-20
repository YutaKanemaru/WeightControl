import Foundation

/// ヘルスケアの実績から見た、ふだんの運動量のまとめ。
nonisolated struct ActivitySummary: Equatable, Sendable {
    /// 平均に使った日数（データがあった日だけ）
    let dayCount: Int
    /// 1 日あたりの平均歩数
    let averageSteps: Double
    /// 1 日あたりの平均アクティブエネルギー（kcal）
    let averageActiveEnergyKcal: Double
    /// 1 日あたりの平均運動時間（分）
    let averageActiveMinutes: Double
    /// 実績から見た活動量の目安
    let suggestedLevel: ActivityLevel
}

/// ヘルスケアの歩数・運動時間から、プロフィールの「活動量」の目安を出します。
///
/// あくまで目安です。歩数と、1 週間の運動時間のそれぞれで段階を出し、高い方を採用します。
/// （歩数が少なくても、水泳や筋トレをしている人を低く見積もらないため）
nonisolated enum ActivityLevelEstimator {
    /// 平均を出すのに必要な、データのある日数
    static let minimumDays = 7

    /// 歩数による段階の境目（1 日の平均歩数）。よく使われる目安の値です。
    static let stepThresholds: [(minimumSteps: Double, level: ActivityLevel)] = [
        (12_500, .veryActive),
        (10_000, .active),
        (7_500, .moderate),
        (5_000, .light),
    ]

    /// 運動時間による段階の境目（1 週間の運動時間、分）。週 150 分は WHO の推奨する運動量の目安です。
    static let weeklyMinuteThresholds: [(minimumMinutes: Double, level: ActivityLevel)] = [
        (450, .veryActive),
        (300, .active),
        (150, .moderate),
        (60, .light),
    ]

    /// データがある日が `minimumDays` 日未満なら nil（判断するには少なすぎるため）。
    static func summarize(_ activities: [DailyActivity]) -> ActivitySummary? {
        let days = activities.filter(\.hasAnyData)
        guard days.count >= minimumDays else { return nil }

        let count = Double(days.count)
        let averageSteps = days.map(\.steps).reduce(0, +) / count
        let averageEnergy = days.map(\.activeEnergyKcal).reduce(0, +) / count
        let averageMinutes = days.map { Double($0.activeMinutes) }.reduce(0, +) / count

        let stepLevel = stepThresholds.first { averageSteps >= $0.minimumSteps }?.level ?? .sedentary
        let minuteLevel = weeklyMinuteThresholds.first { averageMinutes * 7 >= $0.minimumMinutes }?.level ?? .sedentary

        return ActivitySummary(
            dayCount: days.count,
            averageSteps: averageSteps,
            averageActiveEnergyKcal: averageEnergy,
            averageActiveMinutes: averageMinutes,
            suggestedLevel: rank(of: stepLevel) >= rank(of: minuteLevel) ? stepLevel : minuteLevel
        )
    }

    /// 活動量の段階の順番（sedentary が 0、veryActive が最大）
    static func rank(of level: ActivityLevel) -> Int {
        ActivityLevel.allCases.firstIndex(of: level) ?? 0
    }
}
