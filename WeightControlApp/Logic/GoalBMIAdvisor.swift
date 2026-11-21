import Foundation

/// 目標体重の BMI について、画面に出すひとこと。
///
/// どれになっても保存はできます（止めるのではなく、理由と直し方を見せる方針。docs/BMI_GOAL.md）。
nonisolated enum GoalBMIVerdict: Equatable, Sendable {
    /// 目標の BMI が 18.5 未満（増やす目標ではない）。注意を出し、`suggestedWeightKg`（BMI 18.5 の体重）に直すボタンを出す。
    case belowNormal(suggestedWeightKg: Double)
    /// 目標の BMI は 18.5 未満だが、低めの体重から増やしていく目標。補足として 18.5 の体重を示す。
    case gainingTowardNormal(minimumNormalWeightKg: Double)
    /// 目標の BMI が 18.5 以上 25 未満
    case normal
    /// 目標の BMI が 25 以上で、減らす目標。「最初の一歩」としてほめ、5〜10% 減を中間の目安に示す。
    /// `firstStepWeightKg` は目標が 5% 減より大きいときだけ（「まず 5% 減を目標にする」ボタン用）。
    case firstStep(fivePercentWeightKg: Double, tenPercentWeightKg: Double, firstStepWeightKg: Double?)
    /// 目標の BMI が 25 以上で、減らす目標ではない（増やす・キープ・体重の記録なし）。注意を出す。
    /// `isGaining` は、記録から見て増やす目標だと分かっているとき true。
    case aboveNormal(maximumNormalWeightKg: Double, isGaining: Bool)
}

/// 目標体重の BMI の目安と判定結果。画面はこれを並べるだけにします。
nonisolated struct GoalBMIAdvice: Equatable, Sendable {
    /// 目標体重の BMI
    var goalBMI: Double
    /// 目標体重の BMI の区分
    var goalBand: BMIBand
    /// いまの体重の BMI。体重の記録がなければ nil。
    var currentBMI: Double?
    /// この身長での「ふつう」の範囲（kg、0.1 kg 単位）
    var normalRangeKg: ClosedRange<Double>
    /// 標準体重（BMI 22、kg）
    var standardWeightKg: Double
    /// 判定
    var verdict: GoalBMIVerdict

    /// ホームにカードを出して見直しを促すか（低めの目標と、高めへ増やす目標だけ）
    var needsHomeAttention: Bool {
        switch verdict {
        case .belowNormal: true
        case .aboveNormal(_, let isGaining): isGaining
        case .gainingTowardNormal, .normal, .firstStep: false
        }
    }
}

/// 目標体重の BMI を、いまの体重・身長と合わせて判定します。
///
/// ペースの判定（`GoalSafetyChecker`）とは別に行います。どちらも医療的な判断ではなく、一般的な目安です。
nonisolated enum GoalBMIAdvisor {
    /// これより小さい差なら「キープ」とみなす（kg）。ホームの判定（`HomeDashboardBuilder.maintainToleranceKg`）と同じ値。
    static let maintainToleranceKg = 0.1
    /// 高めの BMI から減らすときの、中間の目安（今の体重に対する割合）
    static let firstStepLossRatio = 0.05
    static let secondStepLossRatio = 0.10

    /// - Parameters:
    ///   - targetWeightKg: 目標体重（kg）。nil なら判定しない。
    ///   - currentWeightKg: いまの体重の目安（kg）。記録がなければ nil。
    ///   - heightCm: 身長（cm）。nil や 0 以下なら判定しない。
    static func advice(targetWeightKg: Double?, currentWeightKg: Double?, heightCm: Double?) -> GoalBMIAdvice? {
        guard let targetWeightKg, targetWeightKg > 0, let heightCm, heightCm > 0 else { return nil }

        let goalBMI = BodyMetrics.bmi(weightKg: targetWeightKg, heightCm: heightCm)
        let band = BodyMetrics.band(forBMI: goalBMI)
        let minimumNormalKg = BodyMetrics.minimumNormalWeightKg(heightCm: heightCm)
        let maximumNormalKg = BodyMetrics.maximumNormalWeightKg(heightCm: heightCm)

        let isLosing = currentWeightKg.map { targetWeightKg < $0 - maintainToleranceKg } ?? false
        let isGaining = currentWeightKg.map { targetWeightKg > $0 + maintainToleranceKg } ?? false

        let verdict: GoalBMIVerdict
        switch band {
        case .low:
            verdict = isGaining
                ? .gainingTowardNormal(minimumNormalWeightKg: minimumNormalKg)
                : .belowNormal(suggestedWeightKg: minimumNormalKg)
        case .normal:
            verdict = .normal
        case .high:
            if isLosing, let currentWeightKg {
                let fivePercentKg = roundedToTenth(currentWeightKg * (1 - firstStepLossRatio))
                let tenPercentKg = roundedToTenth(currentWeightKg * (1 - secondStepLossRatio))
                verdict = .firstStep(
                    fivePercentWeightKg: fivePercentKg,
                    tenPercentWeightKg: tenPercentKg,
                    firstStepWeightKg: targetWeightKg < fivePercentKg ? fivePercentKg : nil
                )
            } else {
                verdict = .aboveNormal(maximumNormalWeightKg: maximumNormalKg, isGaining: isGaining)
            }
        }

        return GoalBMIAdvice(
            goalBMI: goalBMI,
            goalBand: band,
            currentBMI: currentWeightKg.map { BodyMetrics.bmi(weightKg: $0, heightCm: heightCm) },
            normalRangeKg: minimumNormalKg...maximumNormalKg,
            standardWeightKg: BodyMetrics.standardWeightKg(heightCm: heightCm),
            verdict: verdict
        )
    }

    /// 0.1 kg 単位に四捨五入
    static func roundedToTenth(_ kg: Double) -> Double {
        (kg * 10).rounded() / 10
    }
}
