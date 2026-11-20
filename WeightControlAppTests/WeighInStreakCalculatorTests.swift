import Foundation
import Testing
@testable import WeightControlApp

/// 連続記録日数（WeighInStreakCalculator）のテスト
struct WeighInStreakCalculatorTests {

    /// 日本時間で日付を区切るカレンダー（実行する環境のタイムゾーンに左右されないよう固定）
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 「今日」= 2026-11-20 の 21:00（日本時間）
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 21))!
    }

    /// 今日から days 日前の、指定した時刻
    private func daysAgo(_ days: Int, hour: Int = 7) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: today)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func streak(_ dates: [Date]) -> Int {
        WeighInStreakCalculator.currentStreak(dates: dates, today: today, calendar: calendar)
    }

    @Test("記録がなければ 0")
    func noRecords() {
        #expect(streak([]) == 0)
    }

    @Test("今日だけ記録していれば 1")
    func onlyToday() {
        #expect(streak([daysAgo(0)]) == 1)
    }

    @Test("今日・昨日・おととい と続いていれば 3（順番はバラバラでも OK）")
    func threeDays() {
        #expect(streak([daysAgo(1), daysAgo(0), daysAgo(2)]) == 3)
    }

    @Test("同じ日に何回記録しても 1 日として数える")
    func sameDayCountsOnce() {
        #expect(streak([daysAgo(0, hour: 7), daysAgo(0, hour: 20), daysAgo(1)]) == 2)
    }

    @Test("今日まだ記録していなくても、昨日まで続いていれば途切れていない")
    func notYetRecordedToday() {
        #expect(streak([daysAgo(1), daysAgo(2)]) == 2)
    }

    @Test("2 日以上あいたら 0")
    func brokenStreak() {
        #expect(streak([daysAgo(2), daysAgo(3)]) == 0)
    }

    @Test("途中で 1 日抜けたら、そこまでで数えるのをやめる")
    func gapStopsCounting() {
        #expect(streak([daysAgo(0), daysAgo(1), daysAgo(3), daysAgo(4)]) == 2)
    }

    @Test("日付の区切りは 0 時（23:30 と翌 0:30 は別の日）")
    func midnightBoundary() {
        let lateLastNight = daysAgo(1, hour: 23)
        let earlyToday = daysAgo(0, hour: 0)
        #expect(streak([lateLastNight, earlyToday]) == 2)
    }
}
