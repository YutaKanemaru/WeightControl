import Foundation

/// 「何日離れているか」「n 日後はいつか」を、カレンダー（暦）に沿って計算する小さな道具箱。
///
/// 1 日 = 86,400 秒 と決め打ちにすると、サマータイムの切り替え日などで 1 日ずれることがあります。
/// `Calendar` に計算を任せることで、そうしたずれを防いでいます。
nonisolated enum DayMath {
    /// `start` の日から `end` の日まで、何日離れているか（時刻は無視して日付だけで数える）。
    /// `end` の方が前なら負の数になります。
    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// `date` の日の 0 時から `days` 日後の 0 時。
    static func date(byAddingDays days: Int, to date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start
    }
}
