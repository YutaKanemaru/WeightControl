import Foundation

/// 目標の期限の決め方（目標を決めるときに選ぶ「ペース」）。
///
/// 保存データ（`WeightGoal`）には文字列（`rawValue`）で保存します。
nonisolated enum GoalPaceMode: String, CaseIterable, Identifiable, Sendable {
    /// ゆるやか：1 週間に体重の 0.5 %（増やすときは 0.25 %）。初回設定の最初の選択
    case gentle
    /// ハード：1 週間に体重の 1 %（増やすときは 0.5 %）。このアプリの上限いっぱい
    case hard
    /// 自分で決める：期限の日付を自分で選ぶ（今までの方法。以前に保存した目標もこれ）
    case manual

    var id: String { rawValue }

    /// 1 週間に変える体重の割合（体重に対して）。「自分で決める」は割合を持たないので nil。
    ///
    /// ハードは `GoalSafetyChecker` の上限をそのまま使い、ゆるやかはその半分にします。
    /// 上限を変えると、ハードとゆるやかも自動でついてきます。
    func weeklyRatio(isLosing: Bool) -> Double? {
        let limit = isLosing ? GoalSafetyChecker.maxWeeklyLossRatio : GoalSafetyChecker.maxWeeklyGainRatio
        switch self {
        case .gentle: return limit / 2
        case .hard: return limit
        case .manual: return nil
        }
    }
}

/// 期限の計算に使う、1 日のカロリーの目安。
nonisolated struct DeadlineEnergy: Equatable, Sendable {
    /// 1 日の消費カロリーの目安（TDEE, kcal）
    var tdeeKcal: Double
    /// 摂取カロリーの下限（kcal）。基礎代謝と、男性 1500・女性 1200 kcal の大きいほう
    var minimumIntakeKcal: Double
}

/// アプリが提案する期限。
nonisolated struct GoalDeadlineSuggestion: Equatable, Sendable {
    /// 提案する期限（その日の 0 時）
    var deadline: Date
    /// 今日から期限までの日数
    var days: Int
    /// 1 週間に変える体重（kg）。減らすときはマイナス
    var weeklyChangeKg: Double
    /// 食事の下限を守るために、モードのペースよりゆっくりにしたとき true
    var isLimitedByIntakeFloor: Bool
    /// 食事の下限のため、ゆるやかとハードが同じ期限になるとき true
    var isSameForAllModes: Bool
    /// 期限が 2 年（`GoalForecaster.horizonDays`）より先のとき true（手前の目標をすすめる）
    var isBeyondHorizon: Bool
}

/// 期限の提案の結果。
nonisolated enum GoalDeadlineProposal: Equatable, Sendable {
    /// いまの体重がもう目標とほぼ同じ（0.1 kg 以内）なので、期限は出さない
    case alreadyAtGoal
    /// 食事の下限を守ると、食事を控えるだけではほとんど減らせない（消費カロリーが下限とほぼ同じ）
    case notReachableByDiet
    /// 提案できた
    case proposed(GoalDeadlineSuggestion)

    /// 提案した期限。提案できなければ nil。
    var deadline: Date? {
        if case .proposed(let suggestion) = self { suggestion.deadline } else { nil }
    }
}

/// 期限までの長さの、ざっくりした言い方（「約 3 か月」など）。
nonisolated enum GoalDuration: Equatable, Sendable {
    /// 2 週間未満は日数で
    case days(Int)
    /// 2 か月（60 日）未満は週で（四捨五入）
    case weeks(Int)
    /// 1 年未満は、半月きざみ（切り捨て）。`half` が true なら「か月半」
    case months(Int, half: Bool)
    /// 1 年以上は、年と月（月は切り捨て）
    case years(Int, months: Int)
}

/// 目標体重とペース（ゆるやか／ハード）から、目標に届く期限を提案します。
///
/// 仕様は `docs/GOAL_DEADLINE.md`。
///
///     差（kg）   ＝ |目標体重 − 今の体重|
///     週のペース ＝ 今の体重 × モードの割合
///     （減らすときだけ）週のペース ＝ min(週のペース, 食事の下限で出せるペース)
///     日数       ＝ 差 ÷ 週のペース × 7 を、日単位で切り上げ
///     期限       ＝ 今日 ＋ 日数
///
/// 一般的な目安をもとにしたアプリの決まりで、医療的な判断ではありません。
nonisolated enum GoalDeadlineProposer {
    /// 1 か月の平均の日数（365.25 ÷ 12）
    private static let daysPerMonth = 30.4375
    /// 食事の下限で出せるペースがこれ（kg/週）より小さいときは「食事だけでは減らしにくい」とする
    /// （1 週間に 10 g では、期限が何十年も先になってしまうため）
    static let minimumWeeklyLossKg = 0.01
    /// 小数の誤差で切り上げすぎないための小さな値
    private static let epsilon = 1e-6

    /// 食事の下限を守ったまま出せる、減量のペース（kg/週、プラスの値）。
    ///
    ///     （消費カロリーの目安 − 下限）× 7 ÷ 7200
    static func maxWeeklyLossKgByIntakeFloor(_ energy: DeadlineEnergy) -> Double {
        max(0, energy.tdeeKcal - energy.minimumIntakeKcal) * 7 / CalorieCalculator.kcalPerKg
    }

    /// 期限を提案します。
    ///
    /// - Parameters:
    ///   - currentWeightKg: 今の体重（kg）。予測の直線の今日の値、なければ最新の記録や初回設定で入れた体重
    ///   - targetWeightKg: 目標体重（kg）
    ///   - mode: ゆるやか／ハード。「自分で決める」を渡したときはゆるやかとして計算します
    ///   - energy: カロリーの目安。分からなければ nil（食事の下限での頭打ちをしない）
    static func propose(
        currentWeightKg: Double,
        targetWeightKg: Double,
        mode: GoalPaceMode,
        energy: DeadlineEnergy?,
        now: Date,
        calendar: Calendar = .current
    ) -> GoalDeadlineProposal {
        let differenceKg = targetWeightKg - currentWeightKg
        guard abs(differenceKg) > GoalSafetyChecker.reachedToleranceKg else { return .alreadyAtGoal }

        let isLosing = differenceKg < 0
        let modeRatio = mode.weeklyRatio(isLosing: isLosing) ?? GoalPaceMode.gentle.weeklyRatio(isLosing: isLosing) ?? 0
        let modeWeeklyKg = currentWeightKg * modeRatio
        var weeklyKg = modeWeeklyKg
        var isLimited = false
        var isSameForAllModes = false

        // 減らすときだけ、食事の下限で出せるペースを上限にする（増やすときは食事を減らさないので関係ない）
        if isLosing, let energy {
            let floorWeeklyKg = maxWeeklyLossKgByIntakeFloor(energy)
            guard floorWeeklyKg >= minimumWeeklyLossKg else { return .notReachableByDiet }
            if floorWeeklyKg < modeWeeklyKg - epsilon {
                weeklyKg = floorWeeklyKg
                isLimited = true
            }
            // ゆるやかのペースでも下限で止まるなら、どちらのモードも同じ期限になる
            let gentleWeeklyKg = currentWeightKg * (GoalPaceMode.gentle.weeklyRatio(isLosing: true) ?? 0)
            isSameForAllModes = floorWeeklyKg < gentleWeeklyKg - epsilon
        }

        let days = max(1, Int((abs(differenceKg) / weeklyKg * 7 - epsilon).rounded(.up)))
        return .proposed(GoalDeadlineSuggestion(
            deadline: DayMath.date(byAddingDays: days, to: now, calendar: calendar),
            days: days,
            weeklyChangeKg: isLosing ? -weeklyKg : weeklyKg,
            isLimitedByIntakeFloor: isLimited,
            isSameForAllModes: isSameForAllModes,
            isBeyondHorizon: days > GoalForecaster.horizonDays
        ))
    }

    /// 期限の計算に使うカロリーの目安を、プロフィールと今の体重から出します（ホームの計算と同じ式）。
    static func energy(
        profile: DashboardProfile,
        weightKg: Double,
        healthActivity: ActivitySummary?,
        now: Date,
        calendar: Calendar = .current
    ) -> DeadlineEnergy {
        let bmr = CalorieCalculator.basalMetabolicRate(
            weightKg: weightKg,
            heightCm: profile.heightCm,
            ageYears: CalorieCalculator.ageYears(birthYear: profile.birthYear, on: now, calendar: calendar),
            sex: profile.sex
        )
        let choice = EnergyExpenditureResolver.choose(
            mode: profile.energyMode,
            activityLevel: profile.activityLevel,
            healthActivity: healthActivity
        )
        return DeadlineEnergy(
            tdeeKcal: EnergyExpenditureResolver.totalDailyEnergyExpenditure(bmrKcal: bmr, source: choice.source),
            minimumIntakeKcal: CalorieCalculator.minimumIntakeKcal(bmrKcal: bmr, sex: profile.sex)
        )
    }

    /// 日数を「約 3 か月」のようなざっくりした長さにします。
    static func duration(days: Int) -> GoalDuration {
        if days < 14 { return .days(days) }
        if days < 60 { return .weeks(Int((Double(days) / 7).rounded())) }
        let months = Double(days) / daysPerMonth
        if months < 12 {
            let halves = Int((months * 2 + epsilon).rounded(.down))
            return .months(halves / 2, half: halves % 2 == 1)
        }
        let wholeMonths = Int((months + epsilon).rounded(.down))
        return .years(wholeMonths / 12, months: wholeMonths % 12)
    }
}
