import Foundation

/// チートデー計画の 1 日分。
nonisolated struct CheatDayPlanDay: Equatable, Sendable {
    /// その日（0 時）
    var date: Date
    /// その日の摂取カロリーの目安（kcal）
    var intakeKcal: Double
    /// チートデー（たくさん食べる日）かどうか
    var isCheatDay: Bool
}

/// チートデー計画（Pro 機能・フェーズ 12）の結果。
nonisolated struct CheatDayPlan: Equatable, Sendable {
    /// 1 週間の予算（kcal）＝ 1 日の目安 × 7。計画を立てても、この合計は変わりません。
    var weeklyBudgetKcal: Double
    /// ふだんの日の摂取カロリーの目安（kcal）
    var regularDayKcal: Double
    /// チートデーの摂取カロリーの目安（kcal）
    var cheatDayKcal: Double
    /// ふだんの日に、いつもの目安から控えめにする量（kcal/日）
    var dailySavingKcal: Double
    /// チートデーに、いつもの目安より多く食べられる量（kcal/日）
    var cheatDayExtraKcal: Double
    /// 下限（基礎代謝など）や 1 日に控えめにできる量の上限のせいで、希望した分まで貯められなかったか
    var isLimited: Bool
    /// 7 日分の目安（`startDate` から順に）
    var days: [CheatDayPlanDay]
}

/// チートデー計画を立てられたかどうか。
nonisolated enum CheatDayPlanResult: Equatable, Sendable {
    /// チートデーの数が範囲外（1〜`CheatDayBudgetPlanner.maximumCheatDays` 日でないと立てられない）
    case invalidCheatDayCount(Int)
    /// 計画できた
    case available(CheatDayPlan)
}

/// 「平日に少しずつカロリーを貯めて、飲み会などの日に使う」1 週間の予算を立てます（Pro 機能）。
///
/// ## 考え方
/// 1 日の目安（推奨摂取カロリー）を 7 日分足したものを **1 週間の予算** とみなします。
/// ふだんの日に少し控えめにした分を、チートデーに回すので、1 週間の合計は変わりません。
/// （体重の変化は、1 日ごとではなく何日か分の合計の収支で決まる、という考え方です）
///
///     ふだんの日 ＝ 1 日の目安 − 控えめにする量
///     チートデー ＝ 1 日の目安 ＋ 控えめにした量の合計 ÷ チートデーの日数
///
/// ## 守ること
/// - ふだんの日も、摂取カロリーの下限（`CalorieCalculator.minimumIntakeKcal`：基礎代謝など）を下回らない。
/// - 1 日に控えめにする量は `maximumDailySavingKcal` まで。急に大きく減らすと続けにくいため。
/// - チートデーは 1 週間に `maximumCheatDays` 日まで。
///
/// どれも一般的な目安で、体調や持病のある人に向けた医療的な指示ではありません。
nonisolated enum CheatDayBudgetPlanner {
    /// 1 週間の日数
    static let daysPerWeek = 7
    /// 1 週間に設定できるチートデーの最大日数
    static let maximumCheatDays = 2
    /// ふだんの日に控えめにする量の上限（kcal/日）
    static let maximumDailySavingKcal = 300.0

    /// - Parameters:
    ///   - dailyTargetKcal: 1 日の摂取カロリーの目安（`IntakeRecommendation.targetKcal`）
    ///   - minimumIntakeKcal: 摂取カロリーの下限（`CalorieCalculator.minimumIntakeKcal`）
    ///   - startDate: 計画の 1 日目。この日から 7 日分を計画します。
    ///   - cheatDates: チートデーにしたい日。7 日の外の日は無視し、同じ日は 1 回と数えます。
    ///   - desiredCheatDayExtraKcal: チートデーに、いつもより多く食べたい量（kcal/日）。
    ///     `nil` なら、守ることの範囲でできるだけ多く貯めます。
    static func plan(
        dailyTargetKcal: Double,
        minimumIntakeKcal: Double,
        startDate: Date,
        cheatDates: [Date],
        desiredCheatDayExtraKcal: Double? = nil,
        calendar: Calendar = .current
    ) -> CheatDayPlanResult {
        // 7 日の中の何日目がチートデーか（0〜6）
        let cheatOffsets = Set(cheatDates.map { DayMath.days(from: startDate, to: $0, calendar: calendar) })
            .filter { (0..<daysPerWeek).contains($0) }
        guard (1...maximumCheatDays).contains(cheatOffsets.count) else {
            return .invalidCheatDayCount(cheatOffsets.count)
        }

        let cheatDayCount = Double(cheatOffsets.count)
        let regularDayCount = Double(daysPerWeek - cheatOffsets.count)

        // ふだんの日に控えめにできる量の上限（下限を割らない・上限を超えない）
        let roomAboveMinimumKcal = max(0, dailyTargetKcal - minimumIntakeKcal)
        let maximumSavingKcal = min(roomAboveMinimumKcal, maximumDailySavingKcal)

        // 希望があれば、その分を貯めるのに必要な量。なければ上限いっぱい。
        let wantedSavingKcal: Double
        if let desiredCheatDayExtraKcal {
            wantedSavingKcal = max(0, desiredCheatDayExtraKcal) * cheatDayCount / regularDayCount
        } else {
            wantedSavingKcal = maximumDailySavingKcal
        }
        let savingKcal = min(wantedSavingKcal, maximumSavingKcal)
        // 小数の誤差で「足りなかった」と判定しないよう、ほんの少しの差は無視する
        let isLimited = wantedSavingKcal - savingKcal > 1e-9

        let regularDayKcal = dailyTargetKcal - savingKcal
        let cheatDayExtraKcal = savingKcal * regularDayCount / cheatDayCount
        let cheatDayKcal = dailyTargetKcal + cheatDayExtraKcal

        let days = (0..<daysPerWeek).map { offset in
            let isCheatDay = cheatOffsets.contains(offset)
            return CheatDayPlanDay(
                date: DayMath.date(byAddingDays: offset, to: startDate, calendar: calendar),
                intakeKcal: isCheatDay ? cheatDayKcal : regularDayKcal,
                isCheatDay: isCheatDay
            )
        }

        return .available(CheatDayPlan(
            weeklyBudgetKcal: dailyTargetKcal * Double(daysPerWeek),
            regularDayKcal: regularDayKcal,
            cheatDayKcal: cheatDayKcal,
            dailySavingKcal: savingKcal,
            cheatDayExtraKcal: cheatDayExtraKcal,
            isLimited: isLimited,
            days: days
        ))
    }
}
