import Foundation
import Testing
@testable import WeightControlApp

/// リマインド通知の予定づくり（WeighInReminderPlanner）のテスト
struct WeighInReminderPlannerTests {

    /// 日本時間で日付を区切るカレンダー（実行する環境のタイムゾーンに左右されないよう固定）
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-11-20 の指定時刻（日本時間）から days 日後
    private func date(daysFromBase days: Int, hour: Int, minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: days, to: base)!
    }

    private let sevenAM = ReminderTime(hour: 7, minute: 0)

    private func plan(time: ReminderTime? = nil, recorded: [Date], now: Date, daysAhead: Int = 7) -> [PlannedReminder] {
        WeighInReminderPlanner.plan(time: time ?? sevenAM, recordedDates: recorded, now: now,
                                    calendar: calendar, daysAhead: daysAhead)
    }

    // MARK: - いつ通知するか

    @Test("時刻前なら、今日を含めて 7 日分つくる")
    func sevenDaysBeforeTime() {
        let reminders = plan(recorded: [], now: date(daysFromBase: 0, hour: 6))
        #expect(reminders.count == 7)
        #expect(reminders.first?.fireDate == date(daysFromBase: 0, hour: 7))
        #expect(reminders.last?.fireDate == date(daysFromBase: 6, hour: 7))
    }

    @Test("時刻を過ぎていたら、今日の分はつくらない")
    func skipTodayAfterTime() {
        let reminders = plan(recorded: [], now: date(daysFromBase: 0, hour: 8))
        #expect(reminders.count == 6)
        #expect(reminders.first?.fireDate == date(daysFromBase: 1, hour: 7))
    }

    @Test("ちょうどその時刻なら、今日の分はつくらない（過去の通知は登録できないため）")
    func skipTodayAtExactTime() {
        let reminders = plan(recorded: [], now: date(daysFromBase: 0, hour: 7))
        #expect(reminders.first?.fireDate == date(daysFromBase: 1, hour: 7))
    }

    @Test("今日もう記録していれば、時刻前でも今日の分はつくらない")
    func skipTodayWhenAlreadyRecorded() {
        let reminders = plan(recorded: [date(daysFromBase: 0, hour: 6)], now: date(daysFromBase: 0, hour: 6, minute: 30))
        #expect(reminders.count == 6)
        #expect(reminders.first?.fireDate == date(daysFromBase: 1, hour: 7))
    }

    @Test("分まで指定した時刻で通知する")
    func usesMinutes() {
        let reminders = plan(time: ReminderTime(hour: 21, minute: 30), recorded: [], now: date(daysFromBase: 0, hour: 12))
        #expect(reminders.first?.fireDate == date(daysFromBase: 0, hour: 21, minute: 30))
    }

    @Test("daysAhead が 0 以下なら何もつくらない")
    func zeroDaysAhead() {
        #expect(plan(recorded: [], now: date(daysFromBase: 0, hour: 6), daysAhead: 0).isEmpty)
    }

    @Test("ID は日付ごと（同じ日の通知は上書きされる）")
    func identifierPerDay() {
        let reminders = plan(recorded: [], now: date(daysFromBase: 0, hour: 6), daysAhead: 2)
        #expect(reminders.map(\.identifier) == ["weighInReminder.2026-11-20", "weighInReminder.2026-11-21"])
    }

    @Test("日付の区切りはカレンダーのタイムゾーンに従う（日本時間 0:30 の記録は、その日の記録）")
    func usesCalendarTimeZone() {
        // 日本時間 11/20 0:30 = UTC では 11/19 15:30。日本時間の区切りでは「今日」の記録
        let reminders = plan(recorded: [date(daysFromBase: 0, hour: 0, minute: 30)], now: date(daysFromBase: 0, hour: 1))
        #expect(reminders.first?.fireDate == date(daysFromBase: 1, hour: 7))
    }

    // MARK: - 文面

    @Test("1 回も記録がなければ「最初の記録」")
    func firstRecord() {
        let reminders = plan(recorded: [], now: date(daysFromBase: 0, hour: 6))
        #expect(reminders.allSatisfy { $0.kind == .firstRecord })
    }

    @Test("昨日まで 5 日連続なら、今日の通知は「5 日連続、6 日目につなげよう」")
    func continueStreakToday() {
        let recorded = (1...5).map { date(daysFromBase: -$0, hour: 7) }
        let reminders = plan(recorded: recorded, now: date(daysFromBase: 0, hour: 6))
        #expect(reminders.first?.kind == .continueStreak(days: 5))
        #expect(reminders.first?.body.contains("5") == true)
        #expect(reminders.first?.body.contains("6") == true)
    }

    @Test("今日記録済みなら、明日の通知には今日までの連続日数が入る")
    func streakIncludesToday() {
        let recorded = (0...3).map { date(daysFromBase: -$0, hour: 7) } // 今日を含めて 4 日連続
        let reminders = plan(recorded: recorded, now: date(daysFromBase: 0, hour: 8))
        #expect(reminders.first?.fireDate == date(daysFromBase: 1, hour: 7))
        #expect(reminders.first?.kind == .continueStreak(days: 4))
    }

    @Test("今日記録すると節目（7 日連続）なら、節目の文面")
    func upcomingMilestone() {
        let recorded = (1...6).map { date(daysFromBase: -$0, hour: 7) }
        let reminders = plan(recorded: recorded, now: date(daysFromBase: 0, hour: 6))
        #expect(reminders.first?.kind == .upcomingMilestone(nextDays: 7))
    }

    @Test("記録しないまま 2 日以上たつ日の通知は、責めずに「再開」の文面")
    func restartForLaterDays() {
        // 昨日まで 3 日連続。今日も明日も記録しなかった場合の、あさっての通知
        let recorded = (1...3).map { date(daysFromBase: -$0, hour: 7) }
        let reminders = plan(recorded: recorded, now: date(daysFromBase: 0, hour: 6))
        #expect(reminders[0].kind == .continueStreak(days: 3)) // 今日
        #expect(reminders[1].kind == .restart)                 // 明日（今日を記録しなかったら途切れている）
        #expect(reminders[2].kind == .restart)
    }

    @Test("前に記録したことがあり、連続が途切れていれば「再開」")
    func restartAfterGap() {
        let reminders = plan(recorded: [date(daysFromBase: -10, hour: 7)], now: date(daysFromBase: 0, hour: 6))
        #expect(reminders.allSatisfy { $0.kind == .restart })
    }

    @Test("文面に責める言葉を使わない")
    func noBlamingWords() {
        let messages = [
            WeighInReminderPlanner.message(streakSoFar: 0, hasEarlierRecord: false),
            WeighInReminderPlanner.message(streakSoFar: 0, hasEarlierRecord: true),
            WeighInReminderPlanner.message(streakSoFar: 2, hasEarlierRecord: true),
            WeighInReminderPlanner.message(streakSoFar: 6, hasEarlierRecord: true),
        ]
        for message in messages {
            for word in ["忘れ", "サボ", "ダメ", "途切れ"] {
                #expect(!message.body.contains(word))
                #expect(!message.title.contains(word))
            }
        }
    }

    // MARK: - ReminderTime

    @Test("範囲外の時刻は 0〜23 時・0〜59 分に収める")
    func clampsTime() {
        #expect(ReminderTime(hour: 25, minute: 70) == ReminderTime(hour: 23, minute: 59))
        #expect(ReminderTime(hour: -1, minute: -5) == ReminderTime(hour: 0, minute: 0))
    }
}
