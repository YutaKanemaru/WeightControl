import Foundation

/// 基礎代謝の計算に使う性別（体のつくりによって式が少し違うため）。
nonisolated enum BiologicalSex: String, CaseIterable, Sendable {
    case male
    case female
}

/// ふだんの活動量。基礎代謝に掛ける「活動係数」を持ちます。
nonisolated enum ActivityLevel: String, CaseIterable, Sendable {
    /// ほとんど座っている
    case sedentary
    /// 軽い運動を週 1〜3 回
    case light
    /// 中くらいの運動を週 3〜5 回
    case moderate
    /// 激しめの運動を週 6〜7 回
    case active
    /// 毎日とても激しい運動・肉体労働
    case veryActive

    /// 活動係数（一般的に使われる目安の値）
    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

/// 推奨摂取カロリーの計算結果。
nonisolated struct IntakeRecommendation: Equatable, Sendable {
    /// 1 日の消費カロリーの目安（TDEE, kcal）
    var tdeeKcal: Double
    /// 1 日の摂取カロリーの目安（kcal）
    var targetKcal: Double
    /// 目安どおり食べたときの 1 日の収支（kcal）。マイナスなら消費の方が多い（やせる方向）。
    var dailyBalanceKcal: Double
    /// 下限（基礎代謝など）に合わせて目安を引き上げたかどうか。
    /// `true` のときは、目標のペースより少しゆっくりになります。
    var isRaisedToMinimum: Bool
}

/// カロリーの計算。
///
/// ## 用語
/// - **基礎代謝（BMR）**：何もせず横になっていても使うエネルギー。Mifflin-St Jeor 式で求めます。
/// - **TDEE**：1 日に使うエネルギーの合計（基礎代謝＋動いた分＋食べ物の消化に使う分）。
/// - **体脂肪 1 kg ≈ 7,200 kcal**：1 kg 減らすには、合計で約 7,200 kcal 消費が上回る必要がある、という目安。
///
/// どれも一般的な目安で、実際の値には個人差があります。
nonisolated enum CalorieCalculator {
    /// 体脂肪 1 kg あたりのエネルギー（kcal）
    static let kcalPerKg = 7200.0
    /// 食べ物の消化に使うエネルギーの割合（TDEE のおよそ 1 割）
    static let thermicEffectOfFoodRatio = 0.1
    /// 摂取カロリーの下限の目安（kcal）。基礎代謝の方が大きければ基礎代謝を下限にします。
    static let minimumIntakeFloorKcal: [BiologicalSex: Double] = [.male: 1500, .female: 1200]

    /// 生まれた年から、`date` の時点のおおよその年齢を出します（誕生日は考えず「年」の差だけ）。
    static func ageYears(birthYear: Int, on date: Date, calendar: Calendar = .current) -> Int {
        max(0, calendar.component(.year, from: date) - birthYear)
    }

    /// 基礎代謝（kcal/日）を Mifflin-St Jeor 式で計算します。
    ///
    ///     男性: 10 × 体重kg + 6.25 × 身長cm − 5 × 年齢 + 5
    ///     女性: 10 × 体重kg + 6.25 × 身長cm − 5 × 年齢 − 161
    static func basalMetabolicRate(weightKg: Double, heightCm: Double, ageYears: Int, sex: BiologicalSex) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    /// TDEE（kcal/日）＝ 基礎代謝 × 活動係数。プロフィールで選んだ活動量から計算します。
    static func totalDailyEnergyExpenditure(bmrKcal: Double, activityLevel: ActivityLevel) -> Double {
        bmrKcal * activityLevel.factor
    }

    /// TDEE（kcal/日）を、実際に動いた量（ヘルスケアの「アクティブエネルギー」の 1 日平均）から計算します。
    ///
    ///     TDEE ＝ 基礎代謝 ＋ 動いた分 ＋ 消化に使う分（TDEE の約 1 割）
    ///          ＝ (基礎代謝 ＋ 動いた分) ÷ 0.9
    ///
    /// 活動係数（自己申告）より、実際の運動の傾向を反映できます。
    static func totalDailyEnergyExpenditure(bmrKcal: Double, averageActiveEnergyKcal: Double) -> Double {
        (bmrKcal + max(0, averageActiveEnergyKcal)) / (1 - thermicEffectOfFoodRatio)
    }

    /// 1 週間に `weeklyChangeKg` だけ体重を変えるのに必要な、1 日あたりのカロリー収支（kcal/日）。
    /// 減量（マイナス）なら、マイナス（＝消費の方を多くする量）になります。
    static func dailyEnergyBalance(forWeeklyChangeKg weeklyChangeKg: Double) -> Double {
        weeklyChangeKg * kcalPerKg / 7
    }

    /// 摂取カロリーの下限（kcal/日）。基礎代謝と、性別ごとの目安のうち大きい方です。
    static func minimumIntakeKcal(bmrKcal: Double, sex: BiologicalSex) -> Double {
        max(bmrKcal, minimumIntakeFloorKcal[sex] ?? 1200)
    }

    /// 1 日の推奨摂取カロリー ＝ TDEE ＋ 目標ペースに必要な収支。
    /// ただし、下限（`minimumIntakeKcal`）より少なくはしません。
    ///
    /// - Parameter plannedWeeklyChangeKg: 目標とするペース（kg/週）。減量ならマイナス。
    static func recommendedIntake(
        tdeeKcal: Double,
        bmrKcal: Double,
        sex: BiologicalSex,
        plannedWeeklyChangeKg: Double
    ) -> IntakeRecommendation {
        let idealKcal = tdeeKcal + dailyEnergyBalance(forWeeklyChangeKg: plannedWeeklyChangeKg)
        let minimumKcal = minimumIntakeKcal(bmrKcal: bmrKcal, sex: sex)
        let targetKcal = max(idealKcal, minimumKcal)
        return IntakeRecommendation(
            tdeeKcal: tdeeKcal,
            targetKcal: targetKcal,
            dailyBalanceKcal: targetKcal - tdeeKcal,
            isRaisedToMinimum: idealKcal < minimumKcal
        )
    }
}
