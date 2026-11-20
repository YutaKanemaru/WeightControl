import Foundation

/// 1 日分のトレンド（ならした体重）。
nonisolated struct TrendPoint: Equatable, Sendable {
    /// その日の 0 時（日付単位にそろえた日時）
    var date: Date
    /// その日に測った体重（kg）。同じ日に何回か測った場合は平均です。
    var measuredKg: Double
    /// EMA でならしたトレンド体重（kg）
    var trendKg: Double
}

/// 日々の体重のブレ（水分・食事・トイレなど）をならして、「本当の流れ」を取り出す計算。
///
/// ## EMA（指数移動平均）とは
/// 「昨日までのトレンド」に「今日の測定値との差」を少しだけ（`smoothing` の割合だけ）足していく平均です。
///
///     今日のトレンド = 昨日のトレンド + 0.1 × (今日の測定値 − 昨日のトレンド)
///
/// 割合が 0.1 なら、1 日で大きく増えても、トレンドはその 1 割しか動きません。
/// そのため、1 日だけの増減には振り回されず、何日も続く変化だけがトレンドに表れます。
///
/// ## 記録が空いた日の扱い
/// 何日か記録がないと、昨日までのトレンドは「古い情報」になります。
/// 空いた日数 `n` に合わせて割合を `1 − (1 − 0.1)^n` に大きくし、毎日記録した場合と同じくらい追いつくようにしています。
nonisolated enum WeightTrendCalculator {
    /// ならし具合の既定値。小さいほどなめらか（そのぶん反応はゆっくり）になります。
    static let defaultSmoothing = 0.1

    /// 同じ日の記録を平均して、1 日 1 件・古い順にそろえます。
    static func dailyAverages(_ points: [WeightPoint], calendar: Calendar = .current) -> [WeightPoint] {
        let byDay = Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
        return byDay
            .map { day, items in
                let total = items.reduce(0) { $0 + $1.weightKg }
                return WeightPoint(date: day, weightKg: total / Double(items.count))
            }
            .sorted { $0.date < $1.date }
    }

    /// 記録からトレンドを計算します。戻り値は 1 日 1 件・古い順です。
    ///
    /// - Parameters:
    ///   - points: 体重の記録（並び順は問いません）
    ///   - smoothing: 1 日あたりのならし割合（0 より大きく 1 以下）
    static func trend(
        _ points: [WeightPoint],
        smoothing: Double = defaultSmoothing,
        calendar: Calendar = .current
    ) -> [TrendPoint] {
        let daily = dailyAverages(points, calendar: calendar)
        guard let first = daily.first else { return [] }

        // 最初のトレンドは、最初の測定値そのものから始めます。
        var result = [TrendPoint(date: first.date, measuredKg: first.weightKg, trendKg: first.weightKg)]
        result.reserveCapacity(daily.count)

        for point in daily.dropFirst() {
            let previous = result[result.count - 1]
            let gapDays = max(1, DayMath.days(from: previous.date, to: point.date, calendar: calendar))
            let effectiveSmoothing = 1 - pow(1 - smoothing, Double(gapDays))
            let trendKg = previous.trendKg + effectiveSmoothing * (point.weightKg - previous.trendKg)
            result.append(TrendPoint(date: point.date, measuredKg: point.weightKg, trendKg: trendKg))
        }
        return result
    }
}
