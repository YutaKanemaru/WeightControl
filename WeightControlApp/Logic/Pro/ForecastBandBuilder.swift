import Foundation

/// グラフに描く「予測の幅（帯）」の 1 点分。同じ日の、早めの見込みと遅めの見込みの体重です。
nonisolated struct ForecastBandPoint: Equatable, Sendable {
    /// その日（0 時）
    var date: Date
    /// 帯の下の端（kg）
    var lowerKg: Double
    /// 帯の上の端（kg）
    var upperKg: Double
}

/// 幅付きの予測（`ForecastRange`）から、グラフの薄い帯の点を作ります（Pro 機能・フェーズ 12）。
///
/// ## 考え方
/// 出発点（今の体重の目安）から、早めのペースの直線と遅めのペースの直線を 2 本引き、
/// その間を塗りつぶすと「このあたりに来そう」という帯になります。
///
/// - 直線が目標体重を越えたら、そこで目標体重に止めます（目標の先までは描かない）。
/// - 帯の終わりは、遅めの見込みで届く日。遅めだと届かない・ずっと先のときは、
///   グラフが横にのびすぎないよう「まん中の見込みまでの日数 × `maximumSpanMultiplier`」で切ります。
/// - 点は `stepDays` 日ごと。線が目標で折れ曲がる日（早めの見込みで届く日）にも点を置きます。
///
/// 描き方（色・透明度など）は画面側（Views）で決めます。
nonisolated enum ForecastBandBuilder {
    /// 帯をのばす最大の長さ：まん中の見込みまでの日数の何倍まで描くか
    static let maximumSpanMultiplier = 2.0
    /// 点を置く間隔（日）
    static let stepDays = 7

    /// - Parameters:
    ///   - range: 幅付きの予測（`ForecastRangeEstimator.estimate` の結果）
    ///   - startKg: 出発点の体重（今の体重の目安。`GoalForecast.currentWeightKg`）
    ///   - goalWeightKg: 目標体重（kg）
    static func band(
        for range: ForecastRange,
        startKg: Double,
        goalWeightKg: Double,
        calendar: Calendar = .current
    ) -> [ForecastBandPoint] {
        let start = calendar.startOfDay(for: range.latestDate)
        let expectedDays = DayMath.days(from: start, to: range.expectedDate, calendar: calendar)
        guard expectedDays > 0 else { return [] }

        let earliestDays = DayMath.days(from: start, to: range.earliestDate, calendar: calendar)
        let capDays = Int((Double(expectedDays) * maximumSpanMultiplier).rounded(.up))
        let endDays: Int
        if let latest = range.latestReachDate {
            endDays = min(DayMath.days(from: start, to: latest, calendar: calendar), capDays)
        } else {
            endDays = capDays
        }
        guard endDays > 0 else { return [] }

        // 点を置く日（何日目か）：0・7・14…と、折れ曲がる日・最後の日
        var offsets = Set(stride(from: 0, to: endDays, by: max(1, stepDays)))
        offsets.insert(endDays)
        if (1..<endDays).contains(earliestDays) { offsets.insert(earliestDays) }

        let optimisticDailyKg = range.optimisticWeeklyChangeKg / 7
        let pessimisticDailyKg = range.pessimisticWeeklyChangeKg / 7
        let isLosing = goalWeightKg < startKg

        /// その日の体重（目標を越えたら目標に止める）
        func weight(dailyKg: Double, day: Int) -> Double {
            let value = startKg + dailyKg * Double(day)
            return isLosing ? max(goalWeightKg, value) : min(goalWeightKg, value)
        }

        return offsets.sorted().map { day in
            let optimisticKg = weight(dailyKg: optimisticDailyKg, day: day)
            let pessimisticKg = weight(dailyKg: pessimisticDailyKg, day: day)
            return ForecastBandPoint(
                date: DayMath.date(byAddingDays: day, to: start, calendar: calendar),
                lowerKg: min(optimisticKg, pessimisticKg),
                upperKg: max(optimisticKg, pessimisticKg)
            )
        }
    }
}
