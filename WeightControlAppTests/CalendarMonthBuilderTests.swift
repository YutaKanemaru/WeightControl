import Foundation
import Testing
@testable import WeightControlApp

/// 月のカレンダーのマス目（CalendarMonthBuilder）のテスト
struct CalendarMonthBuilderTests {

    /// 日本時間・週の始まりを指定したカレンダー（実行する環境に左右されないよう固定）
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("2026年11月（1 日が日曜）・日曜始まり：先頭の空きなし、30 日 + 空き 5 = 35 マス")
    func novemberSundayStart() {
        let cal = calendar(firstWeekday: 1)
        let month = CalendarMonthBuilder.month(containing: date(2026, 11, 15, in: cal), today: date(2026, 11, 20, in: cal), calendar: cal)

        #expect(month.cells.count == 35)
        #expect(month.cells.first??.dayNumber == 1)
        #expect(month.cells.compactMap { $0 }.count == 30)
        #expect(month.cells.suffix(5).allSatisfy { $0 == nil })
        #expect(month.monthStart == cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
    }

    @Test("2026年11月・月曜始まり：1 日（日曜）は 7 列目なので先頭に空きが 6 マス、全部で 42 マス")
    func novemberMondayStart() {
        let cal = calendar(firstWeekday: 2)
        let month = CalendarMonthBuilder.month(containing: date(2026, 11, 1, in: cal), today: date(2026, 11, 20, in: cal), calendar: cal)

        #expect(month.cells.prefix(6).allSatisfy { $0 == nil })
        #expect(month.cells[6]?.dayNumber == 1)
        #expect(month.cells.count == 42)
        #expect(month.cells.count % 7 == 0)
    }

    @Test("2026年2月は 1 日が日曜で 28 日まで：ぴったり 4 週（28 マス）")
    func februaryExactFourWeeks() {
        let cal = calendar(firstWeekday: 1)
        let month = CalendarMonthBuilder.month(containing: date(2026, 2, 10, in: cal), today: date(2026, 11, 20, in: cal), calendar: cal)
        #expect(month.cells.count == 28)
        #expect(month.cells.allSatisfy { $0 != nil })
    }

    @Test("うるう年の 2028年2月は 29 日まである")
    func leapYearFebruary() {
        let cal = calendar()
        let month = CalendarMonthBuilder.month(containing: date(2028, 2, 1, in: cal), today: date(2026, 11, 20, in: cal), calendar: cal)
        #expect(month.cells.compactMap { $0 }.last?.dayNumber == 29)
    }

    @Test("今日のマスに印がつき、それより後の日は「未来」になる")
    func todayAndFuture() {
        let cal = calendar()
        let month = CalendarMonthBuilder.month(containing: date(2026, 11, 1, in: cal), today: date(2026, 11, 20, hour: 23, in: cal), calendar: cal)
        let days = month.cells.compactMap { $0 }

        #expect(days.filter(\.isToday).map(\.dayNumber) == [20])
        #expect(days.first { $0.dayNumber == 20 }?.isFuture == false)
        #expect(days.first { $0.dayNumber == 19 }?.isFuture == false)
        #expect(days.first { $0.dayNumber == 21 }?.isFuture == true)
    }

    @Test("各マスの日付は、その日の 0 時")
    func cellDatesAreStartOfDay() {
        let cal = calendar()
        let month = CalendarMonthBuilder.month(containing: date(2026, 11, 1, in: cal), today: date(2026, 11, 20, in: cal), calendar: cal)
        for cell in month.cells.compactMap({ $0 }) {
            #expect(cell.date == cal.startOfDay(for: cell.date))
            #expect(cal.component(.day, from: cell.date) == cell.dayNumber)
        }
    }

    @Test("曜日の並び：日曜始まりは 日〜土、月曜始まりは 月〜日")
    func weekdayOrder() {
        let sunday = CalendarMonthBuilder.month(containing: date(2026, 11, 1, in: calendar(firstWeekday: 1)), calendar: calendar(firstWeekday: 1))
        #expect(sunday.weekdayNumbers == [1, 2, 3, 4, 5, 6, 7])
        #expect(sunday.weekdaySymbols == ["日", "月", "火", "水", "木", "金", "土"])

        let monday = CalendarMonthBuilder.month(containing: date(2026, 11, 1, in: calendar(firstWeekday: 2)), calendar: calendar(firstWeekday: 2))
        #expect(monday.weekdayNumbers == [2, 3, 4, 5, 6, 7, 1])
        #expect(monday.weekdaySymbols == ["月", "火", "水", "木", "金", "土", "日"])
    }

    @Test("月の移動：年をまたいでも正しく前後の月になる")
    func moveAcrossYears() {
        let cal = calendar()
        let december = cal.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        let january = cal.date(from: DateComponents(year: 2027, month: 1, day: 1))!

        #expect(CalendarMonthBuilder.month(byAdding: 1, to: december, calendar: cal) == january)
        #expect(CalendarMonthBuilder.month(byAdding: -1, to: january, calendar: cal) == december)
    }

    @Test("月の 1 日：31 日から 1 か月ずらしても、月の途中の日にずれない")
    func monthStartFromEndOfMonth() {
        let cal = calendar()
        let jan31 = date(2027, 1, 31, in: cal)
        let start = CalendarMonthBuilder.monthStart(for: jan31, calendar: cal)
        #expect(start == cal.date(from: DateComponents(year: 2027, month: 1, day: 1))!)
        #expect(CalendarMonthBuilder.month(byAdding: 1, to: start, calendar: cal) == cal.date(from: DateComponents(year: 2027, month: 2, day: 1))!)
    }
}
