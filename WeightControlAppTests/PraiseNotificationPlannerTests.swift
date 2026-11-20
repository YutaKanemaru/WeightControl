import Foundation
import Testing
@testable import WeightControlApp

/// ほめる通知の予定づくり（PraiseNotificationPlanner）のテスト
///
/// 基準日 2026-11-20 は金曜日。ふり返りを出す日曜は 11-22（基準日 +2 日）です。
struct PraiseNotificationPlannerTests {

    /// 日本時間で日付を区切るカレンダー（実行する環境のタイムゾーンに左右されないよう固定）
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-11-20（金）の指定時刻（日本時間）から days 日後
    private func date(_ days: Int, hour: Int, minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: days, to: base)!
    }

    /// 指定した日（基準日からの日数）の朝 7:00 に、同じ体重で記録した一覧
    private func records(days: ClosedRange<Int>, weightKg: Double = 70, hour: Int = 7) -> [WeightPoint] {
        days.map { WeightPoint(date: date($0, hour: hour), weightKg: weightKg) }
    }

    private func plan(_ points: [WeightPoint], goal: DashboardGoal? = nil, now: Date) -> [PlannedPraiseNotification] {
        PraiseNotificationPlanner.plan(points: points, goal: goal, now: now, calendar: calendar)
    }

    /// 80 kg から 70 kg を目指す目標
    private let loseGoal = DashboardGoal(targetWeightKg: 70, deadline: Date.distantFuture, startWeightKg: 80)

    // MARK: - 週 1 回のふり返り

    @Test("次の日曜の夜 20:00 に、その週（月〜日）に記録した日数でふり返る")
    func weeklyRecapCountsThisWeek() {
        // 日曜(11/15)は前の週なので数えない。月・火・水・金の 4 日
        let points = [-5, -4, -3, -2, 0].map { WeightPoint(date: date($0, hour: 7), weightKg: 70) }
        let result = plan(points, now: date(0, hour: 12))
        #expect(result.count == 1)
        #expect(result.first?.fireDate == date(2, hour: 20))
        #expect(result.first?.kind == .weeklyRecap(recordedDays: 4, milestone: nil))
        #expect(result.first?.body.contains("4日") == true)
        #expect(result.first?.identifier == "praiseNotification.weeklyRecap.2026-11-22")
    }

    @Test("同じ日に何回記録しても 1 日として数える")
    func sameDayCountsOnce() {
        let points = [WeightPoint(date: date(0, hour: 7), weightKg: 70),
                      WeightPoint(date: date(0, hour: 22), weightKg: 70.5)]
        let result = plan(points, now: date(0, hour: 23))
        #expect(result.first?.kind == .weeklyRecap(recordedDays: 1, milestone: nil))
    }

    @Test("その週に 1 日も記録がなければ、ふり返りは出さない（責めないため）")
    func noRecapWithoutRecords() {
        #expect(plan([], now: date(0, hour: 12)).isEmpty)
        #expect(plan(records(days: -20 ... -10), now: date(0, hour: 12)).isEmpty)
    }

    @Test("日曜の 20:00 ちょうど・過ぎていたら、次の週の日曜に出す")
    func recapAfterSundayEvening() {
        #expect(PraiseNotificationPlanner.nextRecapDate(after: date(2, hour: 19), calendar: calendar) == date(2, hour: 20))
        #expect(PraiseNotificationPlanner.nextRecapDate(after: date(2, hour: 20), calendar: calendar) == date(9, hour: 20))
        #expect(PraiseNotificationPlanner.nextRecapDate(after: date(2, hour: 21), calendar: calendar) == date(9, hour: 20))
    }

    @Test("毎日記録できた週は「毎日」の文面")
    func everyDayRecap() {
        let text = PraiseNotificationPlanner.recapMessage(recordedDays: 7, milestone: nil)
        #expect(text.body.contains("毎日"))
    }

    // MARK: - 連続記録の節目

    @Test("今日の記録で 7 日連続になったら、今日の夜 20:00 にお祝い")
    func streakMilestoneTonight() {
        let result = plan(records(days: -6...0), now: date(0, hour: 8))
        let milestone = result.first { $0.identifier.contains("milestone") }
        #expect(milestone?.fireDate == date(0, hour: 20))
        #expect(milestone?.kind == .milestone(PraiseMilestone(streakDays: 7, goalPercent: nil)))
        #expect(milestone?.body.contains("7日連続") == true)
    }

    @Test("節目に届いた記録が 20:00 より後なら、次の日の夜に出す")
    func lateRecordFiresNextEvening() {
        let points = records(days: -6 ... -1) + [WeightPoint(date: date(0, hour: 21), weightKg: 70)]
        let result = plan(points, now: date(0, hour: 21, minute: 30))
        let milestone = result.first { $0.identifier.contains("milestone") }
        #expect(milestone?.fireDate == date(1, hour: 20))
        #expect(milestone?.identifier == "praiseNotification.milestone.2026-11-20")
    }

    @Test("昨日のお祝いをもう出したあとは、もう一度は登録しない")
    func pastMilestoneNotRepeated() {
        // 昨日（11/19）で 7 日連続。昨日の夜 20:00 はもう過ぎている
        let result = plan(records(days: -7 ... -1), now: date(0, hour: 8))
        #expect(!result.contains { $0.identifier.contains("milestone") })
    }

    @Test("節目でない日数（6 日連続など）ではお祝いしない")
    func noMilestoneForOrdinaryStreak() {
        let result = plan(records(days: -5...0), now: date(0, hour: 8))
        #expect(!result.contains { $0.identifier.contains("milestone") })
    }

    @Test("日曜に節目に届いたら、ふり返りの 1 通にまとめる")
    func milestoneMergedIntoRecap() {
        // 11/16（月）〜11/22（日）の 7 日連続。日曜の朝の時点
        let result = plan(records(days: -4...2), now: date(2, hour: 8))
        #expect(result.count == 1)
        #expect(result.first?.fireDate == date(2, hour: 20))
        #expect(result.first?.kind == .weeklyRecap(recordedDays: 7,
                                                   milestone: PraiseMilestone(streakDays: 7, goalPercent: nil)))
        #expect(result.first?.body.contains("7日連続") == true)
    }

    // MARK: - 目標の節目

    @Test("今日の記録で目標までの道のりの 25% を超えたら、お祝い")
    func goalMilestoneReached() {
        // 15 日間、1 日 0.2 kg ずつ減って今日 77.4 kg（80→70 kg の 26%）。昨日は 77.6 kg（24%）
        let points = (-14...0).map { WeightPoint(date: date($0, hour: 7), weightKg: 77.4 - 0.2 * Double($0)) }
        let percent = PraiseNotificationPlanner.goalMilestone(on: date(0, hour: 7), points: points,
                                                              goal: loseGoal, calendar: calendar)
        #expect(percent == 25)

        let result = plan(points, goal: loseGoal, now: date(0, hour: 8))
        let milestone = result.first { $0.identifier.contains("milestone") }
        #expect(milestone?.kind == .milestone(PraiseMilestone(streakDays: nil, goalPercent: 25)))
        #expect(milestone?.body.contains("25%") == true)
    }

    @Test("前にもう届いていた節目は、もう一度お祝いしない")
    func goalMilestoneNotRepeated() {
        // ずっと 74.9 kg（80→70 kg の 51%）。50% には前の日から届いている
        let points = records(days: -14...0, weightKg: 74.9)
        let percent = PraiseNotificationPlanner.goalMilestone(on: date(0, hour: 7), points: points,
                                                              goal: loseGoal, calendar: calendar)
        #expect(percent == nil)
    }

    @Test("目標体重に届いたら 100%（目標達成）のお祝い")
    func goalAchieved() {
        let text = PraiseNotificationPlanner.milestoneMessage(PraiseMilestone(streakDays: nil, goalPercent: 100))
        #expect(text.title.contains("目標達成"))
    }

    @Test("キープが目標（目標体重＝スタート）なら、目標の節目は出さない")
    func noGoalMilestoneForMaintain() {
        let maintain = DashboardGoal(targetWeightKg: 70, deadline: Date.distantFuture, startWeightKg: 70)
        let percent = PraiseNotificationPlanner.goalMilestone(on: date(0, hour: 7), points: records(days: -14...0),
                                                              goal: maintain, calendar: calendar)
        #expect(percent == nil)
    }

    // MARK: - 文面

    @Test("文面に責める言葉を使わない")
    func noBlamingWords() {
        var texts = (1...7).map { PraiseNotificationPlanner.recapMessage(recordedDays: $0, milestone: nil).body }
        texts.append(PraiseNotificationPlanner.milestoneMessage(PraiseMilestone(streakDays: 7, goalPercent: 50)).body)
        for text in texts {
            for word in ["忘れ", "サボ", "ダメ", "途切れ", "しか"] {
                #expect(!text.contains(word))
            }
        }
    }
}
