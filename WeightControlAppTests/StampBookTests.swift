import Foundation
import Testing
@testable import WeightControlApp

/// カレンダーのスタンプ帳（StampBook）と、運動スタンプのタップのルール（ExerciseStampRule）のテスト
struct StampBookTests {

    /// 日本時間で日付を区切るカレンダー
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, hour: Int = 7, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 「今日」= 2026-11-20 の 21:00（日本時間）
    private var today: Date { date(11, 20, hour: 21) }

    // MARK: - スタンプがあるか

    @Test("体重を記録した日にだけ体重スタンプがある（時刻が違っても同じ日）")
    func weighInStamp() {
        let book = StampBook(weighInDates: [date(11, 18, hour: 7)], exerciseDates: [], calendar: calendar)
        #expect(book.hasWeighIn(on: date(11, 18, hour: 23)))
        #expect(!book.hasWeighIn(on: date(11, 19)))
        #expect(!book.hasExercise(on: date(11, 18)))
    }

    @Test("日付の区切りは 0 時（23:30 の記録は前の日のスタンプ）")
    func midnightBoundary() {
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 23, minute: 30))!
        let book = StampBook(weighInDates: [lateNight], exerciseDates: [], calendar: calendar)
        #expect(book.hasWeighIn(on: date(11, 18)))
        #expect(!book.hasWeighIn(on: date(11, 19)))
    }

    // MARK: - 今月のスタンプ数

    @Test("今月のスタンプ数：同じ日に何回測っても 1 個、体重と運動は別々に数える、ほかの月は数えない")
    func monthCount() {
        let book = StampBook(
            weighInDates: [date(11, 1, hour: 7), date(11, 1, hour: 21), date(11, 2), date(10, 31)],
            exerciseDates: [date(11, 2), date(12, 1)],
            calendar: calendar
        )
        #expect(book.weighInCount(inMonthContaining: today) == 2)
        #expect(book.exerciseCount(inMonthContaining: today) == 1)
        #expect(book.stampCount(inMonthContaining: today) == 3)
        #expect(book.stampCount(inMonthContaining: date(10, 15)) == 1)
    }

    @Test("同じ月でも年が違えば数えない")
    func differentYear() {
        let book = StampBook(weighInDates: [date(11, 5, year: 2025)], exerciseDates: [], calendar: calendar)
        #expect(book.stampCount(inMonthContaining: today) == 0)
    }

    // MARK: - 連続日数

    @Test("体重の連続記録：今日まだでも、昨日まで続いていれば途切れていない")
    func weighInStreak() {
        let book = StampBook(weighInDates: [date(11, 19), date(11, 18), date(11, 17)], exerciseDates: [], calendar: calendar)
        #expect(book.weighInStreak(today: today) == 3)
    }

    @Test("体重か運動のどちらかがあれば、スタンプの連続日数はつながる")
    func anyStampStreak() {
        let book = StampBook(
            weighInDates: [date(11, 20), date(11, 18)],
            exerciseDates: [date(11, 19)],
            calendar: calendar
        )
        #expect(book.weighInStreak(today: today) == 1)
        #expect(book.anyStampStreak(today: today) == 3)
    }

    // MARK: - 運動スタンプのタップ

    @Test("スタンプのない過去の日・今日をタップすると、スタンプを押す")
    func tapAdds() {
        #expect(ExerciseStampRule.action(forTapOn: date(11, 20, hour: 8), today: today, hasManualStamp: false, hasAutomaticStamp: false, calendar: calendar) == .add)
        #expect(ExerciseStampRule.action(forTapOn: date(11, 1), today: today, hasManualStamp: false, hasAutomaticStamp: false, calendar: calendar) == .add)
    }

    @Test("自分で押したスタンプがある日をタップすると、取り消す")
    func tapRemoves() {
        #expect(ExerciseStampRule.action(forTapOn: date(11, 19), today: today, hasManualStamp: true, hasAutomaticStamp: false, calendar: calendar) == .remove)
    }

    @Test("未来の日はタップしても何もしない（今日の 23 時台でも、明日は未来）")
    func futureDoesNothing() {
        let lateToday = date(11, 20, hour: 23)
        #expect(ExerciseStampRule.action(forTapOn: date(11, 21, hour: 0), today: lateToday, hasManualStamp: false, hasAutomaticStamp: false, calendar: calendar) == .none)
    }

    @Test("HealthKit から取り込んだスタンプだけの日は、アプリでは消さない")
    func automaticStampIsKept() {
        #expect(ExerciseStampRule.action(forTapOn: date(11, 19), today: today, hasManualStamp: false, hasAutomaticStamp: true, calendar: calendar) == .none)
    }
}
