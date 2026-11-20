import Foundation

/// 幅付きの予測（Pro 機能・フェーズ 12）の結果。
nonisolated struct ForecastRange: Equatable, Sendable {
    /// 期限に届きそうか（幅で見た場合）
    nonisolated enum DeadlineLikelihood: Equatable, Sendable {
        /// 遅めの見込みでも期限までに届く
        case likely
        /// 早めの見込みなら期限に届く（遅めだと届かない）
        case possible
        /// 早めの見込みでも期限に届かない
        case unlikely
        /// 期限の日がもう過ぎている
        case passed
    }

    /// どのくらい信じてよいか（`GoalForecaster` と同じ基準）
    var confidence: ForecastConfidence
    /// 予測に使った期間（直近 21 日）に記録した日数
    var recordedDays: Int
    /// いちばん新しい記録の日（0 時）
    var latestDate: Date
    /// 早めの見込み（楽観）で届く日
    var earliestDate: Date
    /// まん中の見込みで届く日。無料版の予測（`GoalForecaster` の `.willReach`）と同じ日です。
    var expectedDate: Date
    /// 遅めの見込み（悲観）で届く日。遅めのペースだと横ばい・2 年以上先になるときは `nil`
    /// （画面では「3 月 8 日ごろ〜まだ見えない」のように出す想定）。
    var latestReachDate: Date?
    /// 早めの見込みのペース（kg/週）
    var optimisticWeeklyChangeKg: Double
    /// 遅めの見込みのペース（kg/週）
    var pessimisticWeeklyChangeKg: Double
    /// 期限に届きそうか（期限を決めていなければ `nil`）
    var deadlineLikelihood: DeadlineLikelihood?
}

/// 幅付きの予測を出せたかどうか。
nonisolated enum ForecastRangeResult: Equatable, Sendable {
    /// 記録が足りず、まだ予測できない（`GoalForecaster` と同じ条件）
    case insufficientData(recordedDays: Int, requiredDays: Int)
    /// すでに目標体重に届いている
    case reached
    /// 今のペースでは近づいていない（無料版の予測と同じ判断）
    case notApproaching
    /// 幅付きで予測できた
    case available(ForecastRange)
}

/// 「この調子なら 3 月 8 日〜4 月 2 日ごろ」のような、幅のある達成予測を出します（Pro 機能）。
///
/// ## 考え方
/// 無料版の予測（`GoalForecaster`）は、直近 21 日の測った体重に引いた直線の **傾き 1 本** から届く日を出します。
/// でも体重は毎日上下するので、同じ 3 週間でも「もう少し速いペース」「もう少し遅いペース」の直線もありえます。
///
/// そこで、点が直線のまわりにどれくらいばらついているか（傾きの標準誤差）を計算し、
///
///     早めのペース ＝ 傾き ＋ ばらつき 1 つ分（目標に向かう向き）
///     遅めのペース ＝ 傾き − ばらつき 1 つ分
///
/// として、それぞれのペースで届く日を「早めの日〜遅めの日」として出します。
/// 記録がきれいに直線に乗っているほど幅はせまく、ブレが大きいほど幅は広くなります。
///
/// ## 無料版との関係
/// - 出発点（今の体重の目安）とまん中のペースは `GoalForecaster.paceEstimate` そのものを使うので、
///   まん中の日は無料版の予測とぴったり同じです。`GoalForecaster` の結果は何も変えません。
/// - 無料版が「近づいていない」なら、幅付きでも「近づいていない」にそろえます（画面ごとに言うことが違わないように）。
///
/// どれも今のペースが続いた場合の目安で、実際の体重の変化を約束するものではありません。
nonisolated enum ForecastRangeEstimator {
    /// ばらつき（標準誤差）の何倍を幅にするか。1 倍で、おおよそ 7 割の見込みが入る幅の目安です。
    static let spreadMultiplier = 1.0
    /// 幅の最小値：傾きの 1 割。記録が直線にぴったり乗っていても「〜ごろ」と少し幅を持たせるため。
    static let minimumRelativeSpread = 0.1

    static func estimate(
        points: [WeightPoint],
        goalWeightKg: Double,
        deadline: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> ForecastRangeResult {
        // まん中の見込みは無料版の予測をそのまま使う
        let central = GoalForecaster.forecast(
            points: points,
            goalWeightKg: goalWeightKg,
            deadline: nil,
            now: now,
            calendar: calendar
        )
        let forecast: GoalForecast
        switch central {
        case .insufficientData(let recordedDays, let requiredDays):
            return .insufficientData(recordedDays: recordedDays, requiredDays: requiredDays)
        case .available(let value):
            forecast = value
        }

        let expectedDate: Date
        switch forecast.outcome {
        case .reached: return .reached
        case .notApproaching: return .notApproaching
        case .willReach(let date): expectedDate = date
        }

        // 直線の傾きと、そのばらつき
        let dailyChangeKg = forecast.weeklyChangeKg / 7
        let spreadKgPerDay = max(
            slopeStandardError(points: points, calendar: calendar) * spreadMultiplier,
            abs(dailyChangeKg) * minimumRelativeSpread
        )
        // 目標に向かう向き（減量なら -1、増量なら +1）
        let direction: Double = dailyChangeKg < 0 ? -1 : 1
        let optimisticDailyKg = dailyChangeKg + direction * spreadKgPerDay
        let pessimisticDailyKg = dailyChangeKg - direction * spreadKgPerDay

        let remainingKg = goalWeightKg - forecast.currentWeightKg
        let earliestDate = reachDate(
            remainingKg: remainingKg, dailyChangeKg: optimisticDailyKg, from: forecast.latestDate, calendar: calendar
        ) ?? expectedDate  // 早めのペースはまん中より速いので必ず届くが、念のため
        let latestReachDate = reachDate(
            remainingKg: remainingKg, dailyChangeKg: pessimisticDailyKg, from: forecast.latestDate, calendar: calendar
        )

        let likelihood = deadline.map {
            deadlineLikelihood(
                deadline: $0, earliest: earliestDate, latest: latestReachDate, now: now, calendar: calendar
            )
        }

        return .available(ForecastRange(
            confidence: forecast.confidence,
            recordedDays: forecast.recordedDays,
            latestDate: forecast.latestDate,
            earliestDate: min(earliestDate, expectedDate),
            expectedDate: expectedDate,
            latestReachDate: latestReachDate.map { max($0, expectedDate) },
            optimisticWeeklyChangeKg: optimisticDailyKg * 7,
            pessimisticWeeklyChangeKg: pessimisticDailyKg * 7,
            deadlineLikelihood: likelihood
        ))
    }

    /// 直近 21 日の体重に引いた直線の、傾きの標準誤差（kg/日）。`GoalForecaster.paceEstimate` と同じ点を使います。
    static func slopeStandardError(points: [WeightPoint], calendar: Calendar = .current) -> Double {
        let window = GoalForecaster.recentDailyWeights(points, calendar: calendar)
        guard let latest = window.last else { return 0 }
        let samples = window.map { point in
            (x: Double(DayMath.days(from: latest.date, to: point.date, calendar: calendar)), y: point.weightKg)
        }
        guard let fit = LinearRegression.fit(samples) else { return 0 }
        return LinearRegression.slopeStandardError(samples, fit: fit) ?? 0
    }

    /// そのペースで目標に届く日。横ばい・逆向き・2 年以上先なら `nil`。
    /// 判断の基準は `GoalForecaster` と同じです。
    private static func reachDate(
        remainingKg: Double,
        dailyChangeKg: Double,
        from startDate: Date,
        calendar: Calendar
    ) -> Date? {
        let isFlat = abs(dailyChangeKg * 7) < GoalForecaster.flatThresholdKgPerWeek
        let isWrongDirection = (remainingKg < 0) != (dailyChangeKg < 0)
        if isFlat || isWrongDirection { return nil }

        // 小数の誤差で 1 日多く切り上げないよう、ほんの少し引いてから切り上げる（GoalForecaster と同じ）
        let daysNeeded = (remainingKg / dailyChangeKg - 1e-9).rounded(.up)
        guard daysNeeded <= Double(GoalForecaster.horizonDays) else { return nil }
        return DayMath.date(byAddingDays: Int(daysNeeded), to: startDate, calendar: calendar)
    }

    private static func deadlineLikelihood(
        deadline: Date,
        earliest: Date,
        latest: Date?,
        now: Date,
        calendar: Calendar
    ) -> ForecastRange.DeadlineLikelihood {
        if DayMath.days(from: now, to: deadline, calendar: calendar) < 0 { return .passed }
        if let latest, DayMath.days(from: latest, to: deadline, calendar: calendar) >= 0 { return .likely }
        if DayMath.days(from: earliest, to: deadline, calendar: calendar) >= 0 { return .possible }
        return .unlikely
    }
}
