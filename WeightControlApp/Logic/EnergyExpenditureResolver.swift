import Foundation

/// 1 日の消費カロリー（TDEE）を、何から計算するかの設定。
nonisolated enum EnergyExpenditureMode: String, CaseIterable, Sendable {
    /// ヘルスケアに 7 日分以上の運動データがあれば実績、なければプロフィールの活動量（おすすめ・既定）
    case automatic
    /// いつもプロフィールで選んだ活動量（活動係数）を使う
    case activityLevel
    /// ヘルスケアの実績（アクティブエネルギー）を使う。データが足りない間は活動量を使う
    case healthKit
}

/// 実際に使った消費カロリーの計算方法。
nonisolated enum EnergyExpenditureSource: Equatable, Sendable {
    /// 基礎代謝 × 活動係数
    case activityLevel(ActivityLevel)
    /// （基礎代謝 ＋ 1 日の平均アクティブエネルギー）÷ 0.9。`days` は平均に使った日数。
    case healthKit(averageActiveEnergyKcal: Double, days: Int)
}

/// 消費カロリーの計算方法を決めた結果。
nonisolated struct EnergyExpenditureChoice: Equatable, Sendable {
    /// 実際に使う計算方法
    var source: EnergyExpenditureSource
    /// 「ヘルスケアの実績」を選んでいるのに、データが足りず活動量で計算したとき true（画面で一言そえるため）
    var isFallback: Bool
}

/// 設定（`EnergyExpenditureMode`）とヘルスケアのデータから、消費カロリーの計算方法を決め、TDEE を計算します。
///
/// ## ヘルスケアの実績を使える条件
/// - 直近 28 日のうち、運動量のデータがある日が 7 日以上（`ActivityLevelEstimator.minimumDays`）
/// - 1 日の平均アクティブエネルギーが 0 より大きい（歩数だけ読めてカロリーが読めない場合などを除くため）
///
/// 実績のアクティブエネルギーは、Apple Watch があると多め、iPhone だけだと少なめに出やすいので、
/// 自分に合う方を設定で選べるようにしています。
nonisolated enum EnergyExpenditureResolver {
    /// ヘルスケアの運動量のまとめが、消費カロリーの計算に使えるか
    static func isUsable(_ summary: ActivitySummary?) -> Bool {
        guard let summary else { return false }
        return summary.dayCount >= ActivityLevelEstimator.minimumDays && summary.averageActiveEnergyKcal > 0
    }

    /// 計算方法を決めます。
    ///
    /// - Parameters:
    ///   - mode: 設定で選んだ計算方法
    ///   - activityLevel: プロフィールの活動量
    ///   - healthActivity: ヘルスケアの運動量のまとめ（連携していない・データが少ないときは nil）
    static func choose(
        mode: EnergyExpenditureMode,
        activityLevel: ActivityLevel,
        healthActivity: ActivitySummary?
    ) -> EnergyExpenditureChoice {
        let fromProfile = EnergyExpenditureSource.activityLevel(activityLevel)
        switch mode {
        case .activityLevel:
            return EnergyExpenditureChoice(source: fromProfile, isFallback: false)
        case .automatic, .healthKit:
            if isUsable(healthActivity), let summary = healthActivity {
                return EnergyExpenditureChoice(
                    source: .healthKit(averageActiveEnergyKcal: summary.averageActiveEnergyKcal, days: summary.dayCount),
                    isFallback: false
                )
            }
            // 自動なら、活動量を使うのは決まりどおりなので「代わり」ではない
            return EnergyExpenditureChoice(source: fromProfile, isFallback: mode == .healthKit)
        }
    }

    /// 決めた計算方法で、1 日の消費カロリー（TDEE, kcal）を計算します。
    static func totalDailyEnergyExpenditure(bmrKcal: Double, source: EnergyExpenditureSource) -> Double {
        switch source {
        case .activityLevel(let level):
            CalorieCalculator.totalDailyEnergyExpenditure(bmrKcal: bmrKcal, activityLevel: level)
        case .healthKit(let averageActiveEnergyKcal, _):
            CalorieCalculator.totalDailyEnergyExpenditure(bmrKcal: bmrKcal, averageActiveEnergyKcal: averageActiveEnergyKcal)
        }
    }
}
