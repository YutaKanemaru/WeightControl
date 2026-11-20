import Foundation

/// グラフに描く「点線（予測線）」の点を作ります。
///
/// Swift Charts では点を線でつなぐので、ここでは「日付と体重」の点の並びを返すだけです。
/// 描き方（点線にする・色など）は画面側（Views）で決めます。
nonisolated enum ForecastLineBuilder {
    /// 今のペースが続いた場合の予測線。
    ///
    /// - 始点は「今の体重の目安」（直近 3 週間の体重に引いた直線の、最新の記録の日の値）です。
    /// - `stepDays` 日ごとに点を置きます（直線なので点は少なくて構いません）。
    /// - 目標体重を越える日が来たら、その日に「ちょうど目標体重」の点を置いて終わります。
    /// - 目標に届かない場合は `endDate` まで描きます。
    static func projection(
        startDate: Date,
        startKg: Double,
        weeklyChangeKg: Double,
        goalWeightKg: Double?,
        endDate: Date,
        stepDays: Int = 7,
        calendar: Calendar = .current
    ) -> [WeightPoint] {
        let start = calendar.startOfDay(for: startDate)
        let totalDays = DayMath.days(from: start, to: endDate, calendar: calendar)
        let dailyChangeKg = weeklyChangeKg / 7
        let step = max(1, stepDays)

        var points = [WeightPoint(date: start, weightKg: startKg)]
        guard totalDays > 0 else { return points }

        // 目標体重に届く日（届かなければ nil）
        var reachDay: Int?
        if let goal = goalWeightKg, dailyChangeKg != 0 {
            let days = (goal - startKg) / dailyChangeKg
            // 小数の誤差（41.0000001 日など）で 1 日多く切り上げないよう、ほんの少し引いてから切り上げる
            if days > 0 { reachDay = Int((days - 1e-9).rounded(.up)) }
        }
        let lastDay = min(totalDays, reachDay ?? totalDays)

        var day = step
        while day < lastDay {
            points.append(WeightPoint(
                date: DayMath.date(byAddingDays: day, to: start, calendar: calendar),
                weightKg: startKg + dailyChangeKg * Double(day)
            ))
            day += step
        }

        // 最後の点：目標に届く日なら目標体重ちょうど、そうでなければ線の上の値
        let lastKg: Double
        if let reachDay, let goal = goalWeightKg, reachDay <= totalDays {
            lastKg = goal
        } else {
            lastKg = startKg + dailyChangeKg * Double(lastDay)
        }
        points.append(WeightPoint(
            date: DayMath.date(byAddingDays: lastDay, to: start, calendar: calendar),
            weightKg: lastKg
        ))
        return points
    }

    /// 予測結果から、そのままグラフに使える予測線を作ります。
    ///
    /// - 届く見込みがある：届く日まで
    /// - 近づいていない：期限まで（期限がなければ 4 週間先まで）、今の傾向を描く
    /// - もう届いている：線は不要なので空
    static func projection(
        for forecast: GoalForecast,
        goalWeightKg: Double,
        deadline: Date?,
        stepDays: Int = 7,
        calendar: Calendar = .current
    ) -> [WeightPoint] {
        let endDate: Date
        switch forecast.outcome {
        case .reached:
            return []
        case .willReach(let date):
            endDate = date
        case .notApproaching:
            let fourWeeksLater = DayMath.date(byAddingDays: 28, to: forecast.latestDate, calendar: calendar)
            if let deadline, deadline > forecast.latestDate {
                endDate = deadline
            } else {
                endDate = fourWeeksLater
            }
        }
        return projection(
            startDate: forecast.latestDate,
            startKg: forecast.currentWeightKg,
            weeklyChangeKg: forecast.weeklyChangeKg,
            goalWeightKg: goalWeightKg,
            endDate: endDate,
            stepDays: stepDays,
            calendar: calendar
        )
    }

    /// 「期限に間に合わせるなら、このペース」の線（今の体重の目安 → 期限の日に目標体重）。
    /// 期限がもう過ぎている場合は空です。
    static func requiredPace(
        startDate: Date,
        startKg: Double,
        goalWeightKg: Double,
        deadline: Date,
        calendar: Calendar = .current
    ) -> [WeightPoint] {
        guard DayMath.days(from: startDate, to: deadline, calendar: calendar) > 0 else { return [] }
        return [
            WeightPoint(date: calendar.startOfDay(for: startDate), weightKg: startKg),
            WeightPoint(date: calendar.startOfDay(for: deadline), weightKg: goalWeightKg),
        ]
    }
}
