import Foundation

/// 無理のある目標だったときの、修正案。
nonisolated struct GoalCorrection: Equatable, Sendable {
    /// 期限に間に合わせるのに必要なペース（kg/週）。期限が過ぎていれば `nil`。
    var requiredWeeklyChangeKg: Double?
    /// 無理のないペースの上限（kg/週）。減量ならマイナス。
    var maxWeeklyChangeKg: Double
    /// 目標体重はそのままで、無理のないペースで届くいちばん早い期限
    var suggestedDeadline: Date
    /// 期限はそのままで、無理のないペースで届く目標体重（kg、0.1 kg 単位）。期限が過ぎていれば `nil`。
    var suggestedGoalWeightKg: Double?
}

/// 目標のペースが無理のない範囲か。
nonisolated enum GoalSafetyResult: Equatable, Sendable {
    /// もう目標体重に届いている
    case alreadyAtGoal
    /// 無理のないペース。必要なペース（kg/週）付き。
    case safe(requiredWeeklyChangeKg: Double)
    /// ペースが速すぎる。修正案付き。
    case tooAggressive(GoalCorrection)

    /// カロリー計算に使うペース（kg/週）。速すぎる場合は、無理のない上限のペースにします。
    var plannedWeeklyChangeKg: Double {
        switch self {
        case .alreadyAtGoal: 0
        case .safe(let required): required
        case .tooAggressive(let correction): correction.maxWeeklyChangeKg
        }
    }
}

/// 目標（体重と期限）が速すぎないかを確かめ、速すぎるときは現実的な期限・目標体重を提案します。
///
/// 目安：
/// - 減量は 1 週間に体重の 1 % まで（例: 70 kg なら 0.7 kg/週）
/// - 増量は 1 週間に体重の 0.5 % まで（速く増やすと脂肪が増えやすいため）
///
/// 一般的な目安であり、医療的な判断ではありません。
nonisolated enum GoalSafetyChecker {
    /// 減量ペースの上限（体重に対する 1 週間あたりの割合）
    static let maxWeeklyLossRatio = 0.01
    /// 増量ペースの上限（体重に対する 1 週間あたりの割合）
    static let maxWeeklyGainRatio = 0.005
    /// この差以下なら「もう届いている」とみなす（kg）
    static let reachedToleranceKg = 0.1
    /// 小数の誤差で切り上げすぎないための小さな値
    private static let epsilon = 1e-6

    /// 期限に間に合わせるのに必要なペース（kg/週）。期限が今日以前なら `nil`。
    static func requiredWeeklyChangeKg(
        currentWeightKg: Double,
        goalWeightKg: Double,
        deadline: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Double? {
        let daysLeft = DayMath.days(from: now, to: deadline, calendar: calendar)
        guard daysLeft > 0 else { return nil }
        return (goalWeightKg - currentWeightKg) / (Double(daysLeft) / 7)
    }

    /// 無理のないペースの上限（kg/週）。減量ならマイナス。
    static func maxWeeklyChangeKg(currentWeightKg: Double, isLosing: Bool) -> Double {
        isLosing ? -currentWeightKg * maxWeeklyLossRatio : currentWeightKg * maxWeeklyGainRatio
    }

    static func check(
        currentWeightKg: Double,
        goalWeightKg: Double,
        deadline: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> GoalSafetyResult {
        let remainingKg = goalWeightKg - currentWeightKg
        guard abs(remainingKg) > reachedToleranceKg else { return .alreadyAtGoal }

        let isLosing = remainingKg < 0
        let maxWeekly = maxWeeklyChangeKg(currentWeightKg: currentWeightKg, isLosing: isLosing)
        let required = requiredWeeklyChangeKg(
            currentWeightKg: currentWeightKg,
            goalWeightKg: goalWeightKg,
            deadline: deadline,
            now: now,
            calendar: calendar
        )

        if let required, abs(required) <= abs(maxWeekly) + epsilon {
            return .safe(requiredWeeklyChangeKg: required)
        }

        // 目標体重はそのまま → 上限のペースで何日かかるか（切り上げ）
        let daysNeeded = Int((abs(remainingKg) / abs(maxWeekly) * 7 - epsilon).rounded(.up))
        let suggestedDeadline = DayMath.date(byAddingDays: daysNeeded, to: now, calendar: calendar)

        // 期限はそのまま → 上限のペースでどこまで行けるか（今の体重に近い側に 0.1 kg 単位で丸める）
        var suggestedGoal: Double?
        let daysLeft = DayMath.days(from: now, to: deadline, calendar: calendar)
        if daysLeft > 0 {
            let reachableKg = currentWeightKg + maxWeekly * Double(daysLeft) / 7
            suggestedGoal = isLosing
                ? (reachableKg * 10 - epsilon).rounded(.up) / 10
                : (reachableKg * 10 + epsilon).rounded(.down) / 10
        }

        return .tooAggressive(GoalCorrection(
            requiredWeeklyChangeKg: required,
            maxWeeklyChangeKg: maxWeekly,
            suggestedDeadline: suggestedDeadline,
            suggestedGoalWeightKg: suggestedGoal
        ))
    }
}
