import Foundation

/// リバウンド抑制モード（目標に届いたあとに、体重を範囲の中にキープするモード）のキープの範囲。
nonisolated struct MaintenanceRange: Equatable, Sendable {
    /// 範囲の中心（kg）。ふつうは届いた目標体重。
    var centerKg: Double
    /// 下の端（kg）
    var lowerKg: Double
    /// 上の端（kg）
    var upperKg: Double
    /// 下の端を BMI 18.5 の体重まで引き上げたか（そのときは画面で一言そえます）
    var isLowerRaisedForBMI: Bool

    /// `weightKg` が範囲の中か（端ちょうども中とみなす）
    func contains(_ weightKg: Double) -> Bool {
        weightKg >= lowerKg - MaintenanceAdvisor.epsilon && weightKg <= upperKg + MaintenanceAdvisor.epsilon
    }
}

/// 範囲から外れていく向き
nonisolated enum MaintenanceDrift: Equatable, Sendable {
    /// 上の端に向かっている・上に出た
    case up
    /// 下の端に向かっている・下に出た
    case down
}

/// 今の体重の目安が、範囲に対してどこにいるか。
nonisolated enum MaintenanceStatus: Equatable, Sendable {
    /// 範囲の中
    case inRange
    /// 範囲の中だが、今のペースが続くと `daysUntilExit` 日後に範囲から出る（14 日以内のときだけ）
    case nearEdge(drift: MaintenanceDrift, daysUntilExit: Int)
    /// 上の端より `byKg` kg 上
    case above(byKg: Double)
    /// 下の端より `byKg` kg 下
    case below(byKg: Double)

    /// 範囲の中か（「そろそろ端」も中）
    var isInRange: Bool {
        switch self {
        case .inRange, .nearEdge: true
        case .above, .below: false
        }
    }
}

/// リバウンド抑制モードの判定結果。ホーム画面はこれを並べるだけにします。
nonisolated struct MaintenanceResult: Equatable, Sendable {
    /// キープの範囲
    var range: MaintenanceRange
    /// 判定に使った今の体重の目安（kg）
    var currentWeightKg: Double
    /// 範囲に対してどこにいるか
    var status: MaintenanceStatus
    /// 範囲の中が続いている日数（今日を含む）。範囲の外なら 0。`MaintenanceAdvisor.maxCountedDays` で頭打ち。
    var daysInRange: Int
    /// 上の端より上が続いている日数（今日を含む）。上に出ていなければ 0。
    var daysAboveRange: Int
    /// 摂取カロリーの目安に使う、予定の 1 週間の変化（kg/週。範囲の中なら 0）
    var plannedWeeklyChangeKg: Double

    /// 「新しい目標を決めて戻すこともできます」と一言そえるか（上に出たまま 4 週間たったとき）
    var suggestsNewGoal: Bool {
        daysAboveRange >= MaintenanceAdvisor.suggestNewGoalAfterDays
    }
}

/// リバウンド抑制モードの判断のルール（docs/MAINTENANCE_MODE.md）。
///
/// - 範囲は「中心 ± 幅」（最初は ±1.5 kg）。下の端は BMI 18.5 の体重より下げない。
/// - 判定には 1 回ごとの体重ではなく、ホームと同じ **今の体重の目安**（直近 21 日の直線の値、
///   `HomeDashboardBuilder.currentWeightEstimate`）を使う。1 日だけ重かった日に「範囲から出た」と言わないため。
/// - 範囲の外では、摂取カロリーの目安を体重の 0.25 %／週だけ範囲に戻す向きにする。
///
/// SwiftUI / SwiftData には依存しない、ただの計算です。
nonisolated enum MaintenanceAdvisor {
    /// 範囲の幅（中心からの片側、kg）の最初の値
    static let defaultHalfWidthKg = 1.5
    /// 設定で選べる範囲の幅（中心からの片側、kg）
    static let halfWidthChoicesKg: [Double] = [1.0, 1.5, 2.0]
    /// 今のペースが続くと何日以内に範囲から出るとき「そろそろ端」とするか
    static let nearEdgeLookaheadDays = 14
    /// 範囲の外にいるとき、1 週間に体重の何割ずつ戻す計画にするか（0.25 %。期限の「ゆるやか」の半分）
    static let correctionWeeklyRatio = 0.0025
    /// 上に出たまま、この日数たったら「新しい目標を決めて戻すこともできます」とそえる（4 週間）
    static let suggestNewGoalAfterDays = 28
    /// 範囲の中の日数を数えるのは、この日数まで（それより長い人は「365 日以上」と出す）
    static let maxCountedDays = 365
    /// 小数の誤差で端ちょうどの体重が外になるのを防ぐ小さな値
    static let epsilon = 1e-9

    // MARK: - 範囲

    /// キープの範囲。`heightCm` があれば、下の端を BMI 18.5 の体重（0.1 kg 単位で切り上げ）より下げません。
    /// 引き上げた下の端が中心より上になるとき（中心がもともと BMI 18.5 未満）は、下の端を中心にします。
    static func range(centerKg: Double, halfWidthKg: Double, heightCm: Double?) -> MaintenanceRange {
        let width = max(halfWidthKg, 0)
        var lower = centerKg - width
        var raised = false
        if let heightCm, heightCm > 0 {
            let minimumKg = BodyMetrics.minimumNormalWeightKg(heightCm: heightCm)
            if lower < minimumKg - epsilon {
                lower = min(minimumKg, centerKg)
                raised = true
            }
        }
        return MaintenanceRange(centerKg: centerKg, lowerKg: lower, upperKg: centerKg + width, isLowerRaisedForBMI: raised)
    }

    /// 設定からモードを始めるときの中心：今の体重の目安を 0.1 kg 単位に丸めた値。
    static func roundedCenterKg(_ weightKg: Double) -> Double {
        (weightKg * 10).rounded() / 10
    }

    /// 目標に届いたか（ホームで「リバウンド抑制モードを始める」案内を出すか）。
    ///
    /// 今の体重の目安が目標 ±0.1 kg 以内か、目標を通りこしている（減らす目標でさらに下・増やす目標でさらに上）とき。
    /// キープが目標（スタートと目標がほぼ同じ）のときは ±0.1 kg 以内のときだけ。
    static func isGoalAchieved(startKg: Double, currentKg: Double, targetKg: Double) -> Bool {
        if abs(currentKg - targetKg) <= GoalForecaster.reachedToleranceKg + epsilon { return true }
        switch HomeDashboardBuilder.goalDirection(startKg: startKg, targetKg: targetKg) {
        case .lose: return currentKg < targetKg
        case .gain: return currentKg > targetKg
        case .maintain: return false
        }
    }

    // MARK: - 状態

    /// 今の体重の目安と今のペースから、範囲に対してどこにいるかを決めます。
    ///
    /// - Parameter dailyChangeKg: 今のペース（kg/日）。記録が少なく信じにくいときは nil（「そろそろ端」は出しません）。
    static func status(currentKg: Double, dailyChangeKg: Double?, range: MaintenanceRange) -> MaintenanceStatus {
        if currentKg > range.upperKg + epsilon { return .above(byKg: currentKg - range.upperKg) }
        if currentKg < range.lowerKg - epsilon { return .below(byKg: range.lowerKg - currentKg) }

        guard let dailyChangeKg, abs(dailyChangeKg * 7) >= GoalForecaster.flatThresholdKgPerWeek else { return .inRange }
        let drift: MaintenanceDrift = dailyChangeKg > 0 ? .up : .down
        let distanceKg = drift == .up ? range.upperKg - currentKg : currentKg - range.lowerKg
        // 端ちょうどにいて、さらに外へ向かっているときは「あと 1 日」とする
        let days = max(1, Int((distanceKg / abs(dailyChangeKg)).rounded(.up)))
        return days <= nearEdgeLookaheadDays ? .nearEdge(drift: drift, daysUntilExit: days) : .inRange
    }

    /// 摂取カロリーの目安に使う、予定の 1 週間の変化（kg/週）。
    /// 範囲の中（そろそろ端も）は 0 ＝ 維持カロリー。上に出たら −0.25 %、下に出たら ＋0.25 %。
    static func plannedWeeklyChangeKg(status: MaintenanceStatus, currentKg: Double) -> Double {
        switch status {
        case .inRange, .nearEdge: 0
        case .above: -currentKg * correctionWeeklyRatio
        case .below: currentKg * correctionWeeklyRatio
        }
    }

    // MARK: - まとめて判定

    /// 記録から、リバウンド抑制モードの判定をまとめて出します。記録がなければ nil。
    ///
    /// - Parameters:
    ///   - points: 体重の記録（順番はバラバラで OK）
    ///   - range: キープの範囲
    ///   - startDate: モードを始めた日。「範囲の中の日数」はこの日から数えます。
    ///   - now: 「今」とみなす日時
    static func evaluate(
        points: [WeightPoint],
        range: MaintenanceRange,
        startDate: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> MaintenanceResult? {
        let daily = WeightTrendCalculator.dailyAverages(points, calendar: calendar)
        guard let currentKg = HomeDashboardBuilder.currentWeightEstimate(points: daily, calendar: calendar) else { return nil }

        // 「そろそろ端」は、記録が 7 日以上あってペースを信じてよいときだけ
        let pace = GoalForecaster.paceEstimate(points: daily, calendar: calendar)
        let reliableSlope = pace.flatMap { $0.recordedDays >= GoalForecaster.reliableRecordedDays ? $0.dailyChangeKg : nil }
        let currentStatus = Self.status(currentKg: currentKg, dailyChangeKg: reliableSlope, range: range)

        let today = calendar.startOfDay(for: now)
        let startDay = calendar.startOfDay(for: startDate)
        let estimates = dailyEstimates(daily: daily, from: startDay, through: today, calendar: calendar)

        var daysInRange = 0
        if currentStatus.isInRange {
            daysInRange = streakDays(estimates: estimates, startDay: startDay, today: today, calendar: calendar,
                                     breaks: { !range.contains($0) })
        }
        var daysAbove = 0
        if case .above = currentStatus {
            daysAbove = streakDays(estimates: estimates, startDay: startDay, today: today, calendar: calendar,
                                   breaks: { $0 <= range.upperKg + epsilon })
        }

        return MaintenanceResult(
            range: range,
            currentWeightKg: currentKg,
            status: currentStatus,
            daysInRange: daysInRange,
            daysAboveRange: daysAbove,
            plannedWeeklyChangeKg: plannedWeeklyChangeKg(status: currentStatus, currentKg: currentKg)
        )
    }

    /// `day` の日までの記録で見た、今の体重の目安（ホームと同じ考え方）。その日までに記録がなければ nil。
    ///
    /// - Parameter daily: 1 日 1 件・古い順の記録（`WeightTrendCalculator.dailyAverages` の結果）
    static func weightEstimate(asOf day: Date, daily: [WeightPoint], calendar: Calendar = .current) -> Double? {
        let dayStart = calendar.startOfDay(for: day)
        guard let endIndex = daily.lastIndex(where: { calendar.startOfDay(for: $0.date) <= dayStart }) else { return nil }
        let known = Array(daily[...endIndex])
        // 直線を引く期間（直近 21 日）だけを渡すと速い。点が 3 日未満のときは、ホームと同じく全部の記録のならした値を使う
        let latest = known[known.count - 1].date
        let window = known.filter { DayMath.days(from: $0.date, to: latest, calendar: calendar) < GoalForecaster.regressionWindowDays }
        if window.count >= GoalForecaster.minimumRecordedDays {
            return GoalForecaster.paceEstimate(points: window, calendar: calendar)?.currentWeightKg
        }
        return HomeDashboardBuilder.currentWeightEstimate(points: known, calendar: calendar)
    }

    /// 範囲から出た・戻ったの切りかわり（通知に使います）
    nonisolated enum Crossing: Equatable, Sendable {
        /// 範囲から出た
        case left(MaintenanceDrift)
        /// 範囲に戻った
        case returned
    }

    /// `day` の記録で、範囲から出たか・戻ったか。その日に記録がない・切りかわっていないなら nil。
    ///
    /// 前の記録の日の目安と比べるだけなので、何も覚えておかなくても「出た日」「戻った日」に 1 回ずつになります。
    /// モードを始めた日より前の日は見ません（始めた日の前は「範囲の中」だったとみなします）。
    static func crossing(
        on day: Date,
        daily: [WeightPoint],
        range: MaintenanceRange,
        startDate: Date,
        calendar: Calendar = .current
    ) -> Crossing? {
        let dayStart = calendar.startOfDay(for: day)
        let startDay = calendar.startOfDay(for: startDate)
        guard dayStart >= startDay,
              let index = daily.firstIndex(where: { calendar.startOfDay(for: $0.date) == dayStart }),
              let todayKg = weightEstimate(asOf: dayStart, daily: daily, calendar: calendar) else { return nil }

        let previousKg: Double? = {
            guard index > 0 else { return nil }
            let previousDay = calendar.startOfDay(for: daily[index - 1].date)
            guard previousDay >= startDay else { return nil }
            return weightEstimate(asOf: previousDay, daily: daily, calendar: calendar)
        }()
        let wasInRange = previousKg.map(range.contains) ?? true
        let isInRange = range.contains(todayKg)

        switch (wasInRange, isInRange) {
        case (true, false): return .left(todayKg > range.upperKg ? .up : .down)
        case (false, true): return .returned
        default: return nil
        }
    }

    // MARK: - 日数を数える

    /// 記録した日ごとの目安（モードを始めた日以降・今日まで・新しい順に `maxCountedDays` 日分まで）
    private static func dailyEstimates(
        daily: [WeightPoint],
        from startDay: Date,
        through today: Date,
        calendar: Calendar
    ) -> [(day: Date, kg: Double)] {
        let oldest = max(startDay, DayMath.date(byAddingDays: -(maxCountedDays - 1), to: today, calendar: calendar))
        return daily
            .filter { $0.date >= oldest && $0.date <= today }
            .compactMap { point in
                weightEstimate(asOf: point.date, daily: daily, calendar: calendar).map { (day: point.date, kg: $0) }
            }
    }

    /// 今の状態が続いている日数（今日を含む）。
    ///
    /// 新しい記録の日から順にさかのぼって、`breaks` が true になる（状態が違った）いちばん新しい日を探し、
    /// その次の記録の日から今日までを数えます。見つからなければ、始めた日（か `maxCountedDays` 日前）から数えます。
    private static func streakDays(
        estimates: [(day: Date, kg: Double)],
        startDay: Date,
        today: Date,
        calendar: Calendar,
        breaks: (Double) -> Bool
    ) -> Int {
        var streakStart = max(startDay, DayMath.date(byAddingDays: -(maxCountedDays - 1), to: today, calendar: calendar))
        for (index, estimate) in estimates.enumerated().reversed() where breaks(estimate.kg) {
            guard index + 1 < estimates.count else { return 0 }
            streakStart = estimates[index + 1].day
            break
        }
        let days = DayMath.days(from: streakStart, to: today, calendar: calendar) + 1
        return min(max(days, 0), maxCountedDays)
    }

    // MARK: - ほめるメッセージ

    /// リバウンド抑制モード中の「ほめる」メッセージ。責める言い方はしません。
    static func praise(for result: MaintenanceResult) -> PraiseMessage {
        switch result.status {
        case .inRange:
            if result.daysInRange >= 7 {
                return PraiseMessage(kind: .maintenanceKept(days: result.daysInRange),
                                     text: String(localized: "範囲の中で\(result.daysInRange)日キープできています。すばらしい安定感です！"))
            }
            return PraiseMessage(kind: .maintenanceKept(days: result.daysInRange),
                                 text: String(localized: "範囲の中でキープできています。目標に届いた体重を、このまま守っていきましょう。"))
        case .nearEdge(.up, _):
            return PraiseMessage(kind: .maintenanceDrift,
                                 text: String(localized: "記録を続けているから、小さな変化に早く気づけています。今のうちに少し整えれば大丈夫です。"))
        case .nearEdge(.down, _):
            return PraiseMessage(kind: .maintenanceDrift,
                                 text: String(localized: "記録を続けているから、小さな変化に早く気づけています。食事をしっかりとって整えていきましょう。"))
        case .above:
            return PraiseMessage(kind: .maintenanceDrift,
                                 text: String(localized: "記録を続けていることが、いちばんの力です。あせらず、ゆっくり範囲に戻していきましょう。"))
        case .below:
            return PraiseMessage(kind: .maintenanceDrift,
                                 text: String(localized: "記録を続けられています。食事をしっかりとって、ゆっくり範囲に戻していきましょう。"))
        }
    }
}
