import Foundation

/// カレンダーの 1 マス（1 日分）
nonisolated struct CalendarDayCell: Hashable, Sendable {
    /// その日の 0 時
    let date: Date
    /// 日付の数字（1〜31）
    let dayNumber: Int
    /// 今日かどうか
    let isToday: Bool
    /// 今日より後の日かどうか（未来の日にはスタンプを押せない）
    let isFuture: Bool
}

/// 1 か月分のカレンダーの表（7 列のマス目）
nonisolated struct CalendarMonth: Sendable {
    /// その月の 1 日の 0 時
    let monthStart: Date
    /// 列ごとの曜日の番号（1 = 日曜 … 7 = 土曜）。週の始まりの曜日から順に 7 個。
    let weekdayNumbers: [Int]
    /// 列ごとの曜日の短い名前（例: 「日」「月」…）。`weekdayNumbers` と同じ並び。
    let weekdaySymbols: [String]
    /// マス目を左上から順に並べたもの。月の前後の空きマスは nil。数は必ず 7 の倍数。
    let cells: [CalendarDayCell?]
}

/// 月のカレンダーのマス目を作るロジック。
///
/// 「1 日が何曜日か」に合わせて先頭に空きマスを入れ、最後の週も 7 マスになるように空きマスで埋めます。
/// 週の始まり（日曜 or 月曜）は `calendar.firstWeekday` に従います。
nonisolated enum CalendarMonthBuilder {
    /// `date` を含む月の 1 日の 0 時
    static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// `monthStart` の月から `months` か月ずらした月の 1 日（負の数なら前の月）
    static func month(byAdding months: Int, to monthStart: Date, calendar: Calendar) -> Date {
        let start = self.monthStart(for: monthStart, calendar: calendar)
        let shifted = calendar.date(byAdding: .month, value: months, to: start) ?? start
        return self.monthStart(for: shifted, calendar: calendar)
    }

    /// 列ごとの曜日の番号（1 = 日曜 … 7 = 土曜）を、週の始まりから順に返す
    static func weekdayNumbers(calendar: Calendar) -> [Int] {
        (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 }
    }

    /// `date` を含む月のマス目を作る
    ///
    /// - Parameters:
    ///   - date: 表示したい月に含まれる日時（何日でもよい）
    ///   - today: 「今日」とみなす日時。テストで日付を固定できるように引数にしています。
    ///   - calendar: 日付の区切り（タイムゾーン）や週の始まりを決めるカレンダー
    static func month(containing date: Date, today: Date = .now, calendar: Calendar = .current) -> CalendarMonth {
        let start = monthStart(for: date, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30

        // 1 日の曜日が、週の始まりから何列目か（0〜6）
        let firstWeekday = calendar.component(.weekday, from: start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [CalendarDayCell?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<dayCount {
            let day = DayMath.date(byAddingDays: offset, to: start, calendar: calendar)
            cells.append(CalendarDayCell(
                date: day,
                dayNumber: offset + 1,
                isToday: day == todayStart,
                isFuture: day > todayStart
            ))
        }
        // 最後の週を 7 マスにそろえる
        let trailingBlanks = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array(repeating: nil, count: trailingBlanks))

        let numbers = weekdayNumbers(calendar: calendar)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return CalendarMonth(
            monthStart: start,
            weekdayNumbers: numbers,
            weekdaySymbols: numbers.map { symbols[$0 - 1] },
            cells: cells
        )
    }
}
