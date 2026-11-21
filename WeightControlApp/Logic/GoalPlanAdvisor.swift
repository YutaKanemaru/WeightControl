import Foundation

/// 目標の入力画面で、入力中の目標について出す「ひとこと」。
///
/// 画面（`GoalFormSections`）はこの結果を見て、緑の「無理のないペースです」や、
/// オレンジの「少し速めのペースです」＋修正案のボタンを出し分けます。
nonisolated enum GoalPlanAdvice: Equatable, Sendable {
    /// 目標体重がまだ入っていない（または数字として読めない）
    case needsTargetWeight
    /// 体重の記録がまだないので、ペースを判定できない
    case needsCurrentWeight
    /// 今の体重がもう目標体重とほぼ同じ
    case alreadyAtGoal
    /// 無理のないペース。必要なペース（kg/週、減量ならマイナス）と、期限までの日数付き。
    case comfortable(weeklyChangeKg: Double, daysLeft: Int)
    /// ペースが速すぎる。修正案（`GoalSafetyChecker` と同じもの）付き。
    case tooFast(GoalCorrection)
}

/// 入力中の目標を `GoalSafetyChecker` で確かめ、画面に出すひとことを決めます。
///
/// 判定そのもの（週 1 % など）は `GoalSafetyChecker` に任せ、ここでは
/// 「まだ判定できない」場合の振り分けと、期限までの日数の計算だけを行います。
/// ホームの「無理な目標の修正案」と同じ判定になるよう、今の体重には
/// `HomeDashboardBuilder.currentWeightEstimate` の値を渡す想定です。
nonisolated enum GoalPlanAdvisor {
    static func advice(
        targetWeightKg: Double?,
        currentWeightKg: Double?,
        deadline: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> GoalPlanAdvice {
        guard let targetWeightKg else { return .needsTargetWeight }
        guard let currentWeightKg else { return .needsCurrentWeight }

        switch GoalSafetyChecker.check(
            currentWeightKg: currentWeightKg,
            goalWeightKg: targetWeightKg,
            deadline: deadline,
            now: now,
            calendar: calendar
        ) {
        case .alreadyAtGoal:
            return .alreadyAtGoal
        case .safe(let required):
            return .comfortable(
                weeklyChangeKg: required,
                daysLeft: daysLeft(until: deadline, now: now, calendar: calendar)
            )
        case .tooAggressive(let correction):
            return .tooFast(correction)
        }
    }

    /// 期限まであと何日か。期限が今日か過ぎていれば 0。
    static func daysLeft(until deadline: Date, now: Date, calendar: Calendar = .current) -> Int {
        max(0, DayMath.days(from: now, to: deadline, calendar: calendar))
    }
}
