import Foundation

/// 予測をどのくらい信じてよいか。
nonisolated enum ForecastConfidence: Equatable, Sendable {
    /// 記録が 14 日未満。画面では「参考値」と表示する想定です。
    case reference
    /// 記録が 14 日以上。
    case reliable
}

/// 目標体重までの予測結果。
nonisolated struct GoalForecast: Equatable, Sendable {
    /// 目標に向かう見通し
    nonisolated enum Outcome: Equatable, Sendable {
        /// すでに目標体重に届いている（トレンドが目標 ±0.1 kg 以内）
        case reached
        /// 今のペースが続けば、この日に届く見込み
        case willReach(on: Date)
        /// 今のペースでは近づいていない（横ばい・逆方向、または 2 年以上先）
        case notApproaching
    }

    /// 期限に間に合いそうか
    nonisolated enum DeadlineStatus: Equatable, Sendable {
        /// 期限までに届く見込み（またはもう届いている）
        case onTrack
        /// このままだと期限に届かない。期限に間に合わせるのに必要な 1 週間あたりの変化（kg/週、減量ならマイナス）
        case behind(requiredWeeklyChangeKg: Double)
        /// 期限の日がもう過ぎている
        case passed
    }

    /// どのくらい信じてよいか
    var confidence: ForecastConfidence
    /// 予測に使った期間（直近 21 日）に記録した日数
    var recordedDays: Int
    /// いちばん新しい記録の日（0 時）
    var latestDate: Date
    /// 今の体重の目安（kg）。直近 21 日の体重に引いた直線の、いちばん新しい記録の日の値。
    var currentWeightKg: Double
    /// 1 週間あたりの変化（kg/週）。減っていればマイナス。
    var weeklyChangeKg: Double
    /// 目標に向かう見通し
    var outcome: Outcome
    /// 期限に間に合いそうか（期限を決めていなければ `nil`）
    var deadlineStatus: DeadlineStatus?
}

/// 予測を出せたかどうか。
nonisolated enum GoalForecastResult: Equatable, Sendable {
    /// 記録が足りず、まだ予測できない。`requiredDays - recordedDays` 日記録すると予測できます。
    case insufficientData(recordedDays: Int, requiredDays: Int)
    /// 予測できた
    case available(GoalForecast)
}

/// 直近の体重に引いた直線から見た「今の体重の目安」と「今のペース」。
nonisolated struct WeightPaceEstimate: Equatable, Sendable {
    /// いちばん新しい記録の日（0 時）
    var latestDate: Date
    /// 直線を引くのに使った期間（直近 21 日）に記録した日数
    var recordedDays: Int
    /// 今の体重の目安（kg）＝ 直線の、いちばん新しい記録の日の値
    var currentWeightKg: Double
    /// 1 日あたりの変化（kg/日）＝ 直線の傾き。減っていればマイナス。
    var dailyChangeKg: Double

    /// 1 週間あたりの変化（kg/週）
    var weeklyChangeKg: Double { dailyChangeKg * 7 }
}

/// 「この調子だと何日に目標体重に届くか」「期限に間に合うか」を予測します。
///
/// ## 手順
/// 1. 同じ日の記録を平均して、1 日 1 件にそろえる
/// 2. 直近 21 日（3 週間）の **測った体重** に線形回帰（最小二乗法）で直線を引く
/// 3. 直線の「いちばん新しい記録の日の値」を今の体重の目安、傾きを今のペースとする
/// 4. 今の体重の目安から、そのペースで目標体重に届く日を計算する
///
/// ## なぜトレンド（EMA）ではなく、測った体重に直線を引くのか
/// EMA は毎日「差の 1 割」しか動かないので、減っている途中ではいつも実際の体重より上（遅れて）に出ます。
/// その線を出発点にすると、予測が実際より遅く・重く出てしまいます。
/// 3 週間分の体重 20 点ほどに直線を当てはめれば、1 日だけの上下はほかの日と打ち消し合うので、
/// 遅れなしで、しかも 1 日のブレに振り回されにくい「今の体重」と「ペース」が出せます。
/// （グラフのなめらかな線は、見た目のために EMA のまま残しています）
nonisolated enum GoalForecaster {
    /// 予測を出すのに必要な記録日数
    static let minimumRecordedDays = 7
    /// この日数以上あれば「参考値」ではなくなる
    static let reliableRecordedDays = 14
    /// ペースの計算に使う期間（日）。直近 3 週間の記録を、あるだけ使います。
    static let regressionWindowDays = 21
    /// 今の体重の目安と目標の差がこれ以下なら「届いた」とみなす（kg）
    static let reachedToleranceKg = 0.1
    /// 変化がこれより小さければ「横ばい」とみなす（kg/週）
    static let flatThresholdKgPerWeek = 0.01
    /// これより先の予測は出さない（日）。遠すぎる予測は当てにならないため。
    static let horizonDays = 730

    /// 直近 21 日の記録（1 日 1 件・古い順）。
    static func recentDailyWeights(_ points: [WeightPoint], calendar: Calendar = .current) -> [WeightPoint] {
        let daily = WeightTrendCalculator.dailyAverages(points, calendar: calendar)
        guard let latest = daily.last else { return [] }
        return daily.filter {
            DayMath.days(from: $0.date, to: latest.date, calendar: calendar) < regressionWindowDays
        }
    }

    /// 直近 21 日の体重に直線を引いて、今の体重の目安とペースを出します。記録が 7 日未満なら nil。
    static func paceEstimate(points: [WeightPoint], calendar: Calendar = .current) -> WeightPaceEstimate? {
        let window = recentDailyWeights(points, calendar: calendar)
        guard window.count >= minimumRecordedDays, let latest = window.last else { return nil }

        // x = いちばん新しい日から何日前か（マイナス〜0）、y = その日の体重
        let samples = window.map { point in
            (x: Double(DayMath.days(from: latest.date, to: point.date, calendar: calendar)), y: point.weightKg)
        }
        // 記録が 7 日以上あれば x は必ずばらけるので nil にはならないが、念のため「最新の体重・傾き 0」とする
        let fit = LinearRegression.fit(samples) ?? LinearFit(slope: 0, intercept: latest.weightKg)
        return WeightPaceEstimate(
            latestDate: latest.date,
            recordedDays: window.count,
            currentWeightKg: fit.value(at: 0),
            dailyChangeKg: fit.slope
        )
    }

    static func forecast(
        points: [WeightPoint],
        goalWeightKg: Double,
        deadline: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> GoalForecastResult {
        guard let estimate = paceEstimate(points: points, calendar: calendar) else {
            return .insufficientData(
                recordedDays: recentDailyWeights(points, calendar: calendar).count,
                requiredDays: minimumRecordedDays
            )
        }

        let outcome = makeOutcome(
            currentKg: estimate.currentWeightKg,
            goalKg: goalWeightKg,
            dailyChangeKg: estimate.dailyChangeKg,
            from: estimate.latestDate,
            calendar: calendar
        )

        let deadlineStatus = deadline.map {
            makeDeadlineStatus(
                for: $0,
                outcome: outcome,
                currentKg: estimate.currentWeightKg,
                goalKg: goalWeightKg,
                now: now,
                calendar: calendar
            )
        }

        return .available(GoalForecast(
            confidence: estimate.recordedDays >= reliableRecordedDays ? .reliable : .reference,
            recordedDays: estimate.recordedDays,
            latestDate: estimate.latestDate,
            currentWeightKg: estimate.currentWeightKg,
            weeklyChangeKg: estimate.weeklyChangeKg,
            outcome: outcome,
            deadlineStatus: deadlineStatus
        ))
    }

    private static func makeOutcome(
        currentKg: Double,
        goalKg: Double,
        dailyChangeKg: Double,
        from startDate: Date,
        calendar: Calendar
    ) -> GoalForecast.Outcome {
        let remainingKg = goalKg - currentKg
        if abs(remainingKg) <= reachedToleranceKg { return .reached }

        // 横ばい、または目標と逆の向きに動いている
        let isFlat = abs(dailyChangeKg * 7) < flatThresholdKgPerWeek
        let isWrongDirection = (remainingKg < 0) != (dailyChangeKg < 0)
        if isFlat || isWrongDirection { return .notApproaching }

        // 小数の誤差（41.0000001 日など）で 1 日多く切り上げないよう、ほんの少し引いてから切り上げる
        let daysNeeded = (remainingKg / dailyChangeKg - 1e-9).rounded(.up)
        guard daysNeeded <= Double(horizonDays) else { return .notApproaching }

        return .willReach(on: DayMath.date(byAddingDays: Int(daysNeeded), to: startDate, calendar: calendar))
    }

    private static func makeDeadlineStatus(
        for deadline: Date,
        outcome: GoalForecast.Outcome,
        currentKg: Double,
        goalKg: Double,
        now: Date,
        calendar: Calendar
    ) -> GoalForecast.DeadlineStatus {
        if case .reached = outcome { return .onTrack }

        let daysLeft = DayMath.days(from: now, to: deadline, calendar: calendar)
        if daysLeft < 0 { return .passed }

        if case .willReach(let date) = outcome,
           DayMath.days(from: date, to: deadline, calendar: calendar) >= 0 {
            return .onTrack
        }

        // 期限が今日なら、残り 1 日として計算する（0 で割らないため）
        let weeksLeft = Double(max(daysLeft, 1)) / 7
        return .behind(requiredWeeklyChangeKg: (goalKg - currentKg) / weeksLeft)
    }
}
