import Foundation

/// 「何日連続で体重を記録できているか（連続記録日数）」を数えるロジック。
nonisolated enum WeighInStreakCalculator {
    /// 連続記録日数を返します。
    ///
    /// - 同じ日に何回記録しても 1 日として数えます。
    /// - 今日まだ記録していなくても、昨日まで続いていれば「途切れていない」とみなして昨日までの日数を返します
    ///   （朝に測る人が、夜まで「0 日」と表示されてがっかりしないように）。
    /// - 今日も昨日も記録がなければ 0 です。
    ///
    /// - Parameters:
    ///   - dates: 記録した日時の一覧（順番はバラバラで OK）
    ///   - today: 「今日」とみなす日時。テストで日付を固定できるように引数にしています。
    ///   - calendar: 日付の区切り（タイムゾーン）を決めるカレンダー
    static func currentStreak(dates: [Date], today: Date = .now, calendar: Calendar = .current) -> Int {
        // 日時を「その日の 0 時」にそろえて、日ごとの集合にする
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        let todayStart = calendar.startOfDay(for: today)

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return 0 }
        var day: Date
        if days.contains(todayStart) {
            day = todayStart
        } else if days.contains(yesterday) {
            day = yesterday
        } else {
            return 0
        }

        // 1 日ずつさかのぼって、記録がある日を数える
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}
