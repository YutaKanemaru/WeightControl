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
    /// 予測に使った期間（直近 28 日）に記録した日数
    var recordedDays: Int
    /// いちばん新しい記録の日（0 時）
    var latestDate: Date
    /// 今のトレンド体重（kg）
    var currentTrendKg: Double
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

/// 「この調子だと何日に目標体重に届くか」「期限に間に合うか」を予測します。
///
/// ## 手順
/// 1. 記録から EMA のトレンドを作る（`WeightTrendCalculator`）
/// 2. 直近 28 日のトレンドに線形回帰で直線を引き、その傾きを「今のペース（kg/週）」とする
/// 3. 今のトレンド体重から、そのペースで目標体重に届く日を計算する
///
/// 測定値そのものではなくトレンドに直線を引くので、1 日だけの増減で予測が大きく揺れません。
nonisolated enum GoalForecaster {
    /// 予測を出すのに必要な記録日数
    static let minimumRecordedDays = 7
    /// この日数以上あれば「参考値」ではなくなる
    static let reliableRecordedDays = 14
    /// ペースの計算に使う期間（日）。2〜4 週間の範囲で、あるだけ使います。
    static let regressionWindowDays = 28
    /// トレンドと目標の差がこれ以下なら「届いた」とみなす（kg）
    static let reachedToleranceKg = 0.1
    /// 変化がこれより小さければ「横ばい」とみなす（kg/週）
    static let flatThresholdKgPerWeek = 0.01
    /// これより先の予測は出さない（日）。遠すぎる予測は当てにならないため。
    static let horizonDays = 730

    static func forecast(
        points: [WeightPoint],
        goalWeightKg: Double,
        deadline: Date?,
        now: Date,
        smoothing: Double = WeightTrendCalculator.defaultSmoothing,
        calendar: Calendar = .current
    ) -> GoalForecastResult {
        let trend = WeightTrendCalculator.trend(points, smoothing: smoothing, calendar: calendar)
        guard let latest = trend.last else {
            return .insufficientData(recordedDays: 0, requiredDays: minimumRecordedDays)
        }

        // 直近 28 日（いちばん新しい記録の日を含む）のトレンドだけを使う
        let window = trend.filter {
            DayMath.days(from: $0.date, to: latest.date, calendar: calendar) < regressionWindowDays
        }
        guard window.count >= minimumRecordedDays else {
            return .insufficientData(recordedDays: window.count, requiredDays: minimumRecordedDays)
        }

        // x = いちばん新しい日から何日前か（マイナス〜0）、y = トレンド体重
        let samples = window.map { point in
            (x: Double(DayMath.days(from: latest.date, to: point.date, calendar: calendar)), y: point.trendKg)
        }
        // 記録が 7 日以上あれば x は必ずばらけるので nil にはならないが、念のため傾き 0 とする
        let dailyChangeKg = LinearRegression.fit(samples)?.slope ?? 0
        let weeklyChangeKg = dailyChangeKg * 7

        let outcome = makeOutcome(
            currentKg: latest.trendKg,
            goalKg: goalWeightKg,
            dailyChangeKg: dailyChangeKg,
            from: latest.date,
            calendar: calendar
        )

        let deadlineStatus = deadline.map {
            makeDeadlineStatus(
                for: $0,
                outcome: outcome,
                currentKg: latest.trendKg,
                goalKg: goalWeightKg,
                now: now,
                calendar: calendar
            )
        }

        return .available(GoalForecast(
            confidence: window.count >= reliableRecordedDays ? .reliable : .reference,
            recordedDays: window.count,
            latestDate: latest.date,
            currentTrendKg: latest.trendKg,
            weeklyChangeKg: weeklyChangeKg,
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

        let daysNeeded = (remainingKg / dailyChangeKg).rounded(.up)
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
