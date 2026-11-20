import Foundation
import Testing
@testable import WeightControlApp

/// カレンダータブの「まとめ」（CalendarSummaryBuilder）のテスト
struct CalendarSummaryBuilderTests {

    /// 日本時間で日付を区切るカレンダー
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// 「今日」= 2026-11-20 の 21:00（日本時間）
    private var today: Date { date(11, 20, hour: 21) }

    private func summary(weighIns: [Date], exercises: [Date] = []) -> CalendarSummary {
        let book = StampBook(weighInDates: weighIns, exerciseDates: exercises, calendar: calendar)
        return CalendarSummaryBuilder.build(stampBook: book, today: today)
    }

    @Test("記録が 1 つもないときは空の状態（はじめてのひとこと）")
    func empty() {
        let result = summary(weighIns: [])
        #expect(result.streakDays == 0)
        #expect(result.monthStampCount == 0)
        #expect(!result.hasAnyStamp)
        #expect(!result.hasWeighInToday)
        #expect(!result.hasExerciseToday)
        #expect(result.encouragement == .firstStamp)
    }

    @Test("今月のスタンプ数は今日を含む月だけ、体重と運動の合計")
    func monthCounts() {
        let result = summary(
            weighIns: [date(11, 1), date(11, 1, hour: 22), date(11, 19), date(10, 31)],
            exercises: [date(11, 19), date(11, 20), date(10, 30)]
        )
        #expect(result.monthWeighInDays == 2)
        #expect(result.monthExerciseDays == 2)
        #expect(result.monthStampCount == 4)
        #expect(result.hasExerciseToday)
        #expect(!result.hasWeighInToday)
        #expect(result.hasAnyStamp)
    }

    @Test("今日まだでも、昨日まで続いていれば連続記録は途切れない")
    func streakUntilYesterday() {
        let result = summary(weighIns: [date(11, 17), date(11, 18), date(11, 19)])
        #expect(result.streakDays == 3)
        #expect(result.encouragement == .buildingHabit(days: 3))
    }

    @Test("運動スタンプだけがある人は、連続 0 日でも「再開」のひとこと（はじめて扱いにしない）")
    func exerciseOnlyIsNotFirstStamp() {
        let result = summary(weighIns: [], exercises: [date(11, 10)])
        #expect(result.streakDays == 0)
        #expect(result.encouragement == .restart)
    }

    @Test("ひとことの切り替え：0 日・1〜2 日・3〜6 日・7 日以上")
    func encouragementThresholds() {
        #expect(CalendarSummaryBuilder.encouragement(streakDays: 0, hasAnyStamp: false) == .firstStamp)
        #expect(CalendarSummaryBuilder.encouragement(streakDays: 0, hasAnyStamp: true) == .restart)
        #expect(CalendarSummaryBuilder.encouragement(streakDays: 1, hasAnyStamp: true) == .goodStart(days: 1))
        #expect(CalendarSummaryBuilder.encouragement(streakDays: 2, hasAnyStamp: true) == .goodStart(days: 2))
        #expect(CalendarSummaryBuilder.encouragement(streakDays: 3, hasAnyStamp: true) == .buildingHabit(days: 3))
        #expect(CalendarSummaryBuilder.encouragement(streakDays: 6, hasAnyStamp: true) == .buildingHabit(days: 6))
        #expect(CalendarSummaryBuilder.encouragement(streakDays: 7, hasAnyStamp: true) == .habit(days: 7))
        #expect(CalendarSummaryBuilder.encouragement(streakDays: 120, hasAnyStamp: true) == .habit(days: 120))
    }
}
