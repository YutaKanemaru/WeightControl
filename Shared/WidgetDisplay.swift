import Foundation

/// 期限までの残りの表し方
nonisolated enum WidgetDeadlineStatus: Equatable, Sendable {
    /// 期限まであと `days` 日（1 以上）
    case daysLeft(Int)
    /// 今日が期限
    case today
    /// 期限を過ぎた
    case passed
}

/// ウィジェットを描く「その日」に合わせて決める表示のルール（アプリとウィジェットの両方に入り、テストはアプリ側で行う）。
///
/// スナップショットは記録や目標が変わったときにしか作り直されないので、
/// 「期限まで ○ 日」「今日の記録」「連続記録日数」のように日付で変わるものは、表示する日にここで計算します。
nonisolated enum WidgetDisplay {
    /// グラフに出す日数（直近 14 日）
    static let recentDays = 14

    /// 期限まで何日か（時刻は無視して日付だけで数える）
    static func deadlineStatus(deadline: Date, today: Date, calendar: Calendar = .current) -> WidgetDeadlineStatus {
        let days = daysBetween(today, deadline, calendar: calendar)
        if days > 0 { return .daysLeft(days) }
        return days == 0 ? .today : .passed
    }

    /// 今日の記録があるか
    static func hasRecordedToday(_ snapshot: WidgetSnapshot, today: Date, calendar: Calendar = .current) -> Bool {
        guard let latest = snapshot.latestDate else { return false }
        return calendar.isDate(latest, inSameDayAs: today)
    }

    /// 表示してよい連続記録日数。最新の記録が昨日より前なら、もう途切れているので 0。
    ///
    /// 連続記録日数は「今日まだでも、昨日まで続いていれば途切れていない」と数えています（`WeighInStreakCalculator`）。
    /// そのため、最新の記録が今日か昨日なら、作った時点の値をそのまま出せます。
    static func visibleStreakDays(_ snapshot: WidgetSnapshot, today: Date, calendar: Calendar = .current) -> Int {
        guard let latest = snapshot.latestDate else { return 0 }
        let days = daysBetween(latest, today, calendar: calendar)
        return (0...1).contains(days) ? snapshot.streakDays : 0
    }

    /// グラフに出す記録（今日から数えて直近 14 日に入るものだけ）。スナップショットが古くなっても、古い記録が残らないようにする。
    static func visibleRecords(_ snapshot: WidgetSnapshot, today: Date, calendar: Calendar = .current) -> [WidgetWeightRecord] {
        snapshot.recentRecords.filter {
            let days = daysBetween($0.date, today, calendar: calendar)
            return days >= 0 && days < recentDays
        }
    }

    /// 次にウィジェットを描き直してほしい時刻（次の日の 0 時。日付が変わると「期限まで」などが変わるため）
    static func nextRefreshDate(after now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
    }

    /// `start` の日から `end` の日まで何日離れているか（`Logic/DayMath` と同じ考え方。ウィジェットには Logic が入らないのでここにも置く）
    private static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
