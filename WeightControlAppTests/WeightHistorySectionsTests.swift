import Foundation
import Testing
@testable import WeightControlApp

/// 履歴の月ごとの区切り（WeightHistorySections）のテスト
struct WeightHistorySectionsTests {
    private let calendar = TestCalendar.utc

    /// 年・月・日から日付を作る（UTC）
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("記録がなければセクションもない")
    func empty() {
        #expect(WeightHistorySections.byMonth([], calendar: calendar).isEmpty)
    }

    @Test("新しい順の記録を、並び順のまま月ごとに区切る")
    func groupsNewestFirst() {
        let dates = [
            date(2027, 2, 3),
            date(2027, 2, 1),
            date(2027, 1, 31, hour: 23),
            date(2027, 1, 10),
            date(2026, 12, 31),
        ]
        let sections = WeightHistorySections.byMonth(dates, calendar: calendar)
        #expect(sections.map(\.monthStart) == [date(2027, 2, 1, hour: 0), date(2027, 1, 1, hour: 0), date(2026, 12, 1, hour: 0)])
        #expect(sections.map(\.indices) == [[0, 1], [2, 3], [4]])
    }

    @Test("同じ月の記録が離れていても、最初のセクションにまとめる")
    func mergesSameMonth() {
        let dates = [date(2027, 2, 3), date(2027, 1, 10), date(2027, 2, 1)]
        let sections = WeightHistorySections.byMonth(dates, calendar: calendar)
        #expect(sections.map(\.indices) == [[0, 2], [1]])
    }
}
