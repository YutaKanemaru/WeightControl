import Foundation
import Testing
@testable import WeightControlApp

/// ウィジェットに出す数字（WidgetSnapshotBuilder）のテスト。
/// ホームと同じ数字になっているか、直近 14 日の記録の選び方が正しいかを確かめます。
struct WidgetSnapshotBuilderTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int, hour: Int = 0) -> Date { TestCalendar.day(n, hour: hour) }

    private func dashboard(_ points: [WeightPoint], goal: DashboardGoal?, includesPro: Bool = false, now: Date) -> HomeDashboard {
        HomeDashboardBuilder.build(points: points, profile: nil, goal: goal, foods: [], includesPro: includesPro, now: now, calendar: calendar)
    }

    private func build(_ points: [WeightPoint], goal: DashboardGoal?, includesPro: Bool = false, now: Date) -> (WidgetSnapshot, HomeDashboard) {
        let home = dashboard(points, goal: goal, includesPro: includesPro, now: now)
        let snapshot = WidgetSnapshotBuilder.build(points: points, goal: goal, dashboard: home, now: now, calendar: calendar)
        return (snapshot, home)
    }

    @Test("記録も目標もなければ、空のスナップショット")
    func empty() {
        let (snapshot, _) = build([], goal: nil, now: day(0))
        #expect(snapshot.latestWeightKg == nil)
        #expect(snapshot.latestDate == nil)
        #expect(snapshot.recentRecords.isEmpty)
        #expect(snapshot.streakDays == 0)
        #expect(snapshot.goal == nil)
        #expect(snapshot.maintenance == nil)
    }

    @Test("最新の体重はいちばん新しい記録、目標までは最新の体重から（ホームと同じ）")
    func matchesHome() throws {
        // 10 日間、毎日 0.1 kg ずつ減っている。並びはわざとバラバラにする
        let points = (0..<10).map { WeightPoint(date: day($0, hour: 7), weightKg: 70 - Double($0) * 0.1) }.shuffled()
        let goal = DashboardGoal(targetWeightKg: 65, deadline: day(90), startWeightKg: 70)
        let (snapshot, home) = build(points, goal: goal, now: day(9, hour: 12))

        #expect(snapshot.latestDate == day(9, hour: 7))
        #expect(isApproximately(try #require(snapshot.latestWeightKg), 69.1))
        #expect(snapshot.streakDays == home.streakDays)
        #expect(snapshot.streakDays == 10)

        let summary = try #require(snapshot.goal)
        let currentKg = try #require(home.currentWeightKg)
        #expect(summary.targetWeightKg == 65)
        #expect(summary.deadline == day(90))
        // 最新の体重 69.1 kg − 目標 65 kg
        #expect(isApproximately(try #require(summary.remainingKg), 4.1))
        // 進み具合は今の体重の目安から
        #expect(isApproximately(try #require(summary.progress), (70 - currentKg) / 5))
        #expect(summary.isAchieved == false)
        #expect(snapshot.maintenance == nil)
    }

    @Test("最新の体重が目標を通りこしたら isAchieved、残りは出さず進み具合は 1")
    func achieved() throws {
        let points = (0..<7).map { WeightPoint(date: day($0), weightKg: 64.5) }
        let goal = DashboardGoal(targetWeightKg: 65, deadline: day(90), startWeightKg: 70)
        let (snapshot, _) = build(points, goal: goal, now: day(6))
        let summary = try #require(snapshot.goal)
        #expect(summary.isAchieved)
        #expect(summary.remainingKg == nil)
        #expect(summary.progress == 1)
    }

    @Test("目標との差が 0.1 kg 以内なら達成、1 日だけ通りこしても達成（ホームの「目標まで 達成」と同じ）")
    func achievedByLatestWeight() throws {
        var points = (0..<6).map { WeightPoint(date: day($0), weightKg: 66) }
        points.append(WeightPoint(date: day(6), weightKg: 65.05))
        let goal = DashboardGoal(targetWeightKg: 65, deadline: day(90), startWeightKg: 70)
        let (snapshot, _) = build(points, goal: goal, now: day(6))
        #expect(try #require(snapshot.goal).isAchieved)
    }

    @Test("目標を決めたときの体重がなければ、最初の記録から進み具合を出す")
    func progressFromFirstRecord() throws {
        let points = (0..<7).map { WeightPoint(date: day($0), weightKg: 70 - Double($0) * 0.2) }
        let goal = DashboardGoal(targetWeightKg: 60, deadline: day(200), startWeightKg: nil)
        let (snapshot, home) = build(points, goal: goal, now: day(6))
        let currentKg = try #require(home.currentWeightKg)
        #expect(isApproximately(try #require(snapshot.goal?.progress), (70 - currentKg) / 10))
    }

    @Test("キープモード中（Pro）は範囲を入れる")
    func maintenance() throws {
        let points = (0..<7).map { WeightPoint(date: day($0), weightKg: 64) }
        let goal = DashboardGoal(targetWeightKg: 64, deadline: day(90), startWeightKg: 64, maintenanceStartDate: day(0), maintenanceHalfWidthKg: 1.5)
        let (snapshot, home) = build(points, goal: goal, includesPro: true, now: day(6))
        let range = try #require(home.maintenance?.range)
        let summary = try #require(snapshot.maintenance)
        #expect(isApproximately(summary.lowerKg, range.lowerKg))
        #expect(isApproximately(summary.upperKg, range.upperKg))
        #expect(summary.isInRange)
    }

    @Test("Pro を使えないときは、キープモードの情報を入れない")
    func maintenanceWithoutPro() {
        let points = (0..<7).map { WeightPoint(date: day($0), weightKg: 64) }
        let goal = DashboardGoal(targetWeightKg: 64, deadline: day(90), startWeightKg: 64, maintenanceStartDate: day(0))
        let (snapshot, _) = build(points, goal: goal, includesPro: false, now: day(6))
        #expect(snapshot.maintenance == nil)
    }

    // MARK: - 直近 14 日の記録

    @Test("1 日に何回記録しても、その日の平均で 1 日 1 点にする")
    func lastRecordOfDay() {
        let points = [
            WeightPoint(date: day(5, hour: 21), weightKg: 70.4),
            WeightPoint(date: day(5, hour: 7), weightKg: 70.0),
            WeightPoint(date: day(6, hour: 7), weightKg: 69.8),
        ]
        let records = WidgetSnapshotBuilder.recentRecords(points: points, now: day(6, hour: 12), calendar: calendar)
        #expect(records.map(\.date) == [day(5), day(6)])
        #expect(isApproximately(records[0].weightKg, 70.2))
        #expect(isApproximately(records[1].weightKg, 69.8))
    }

    @Test("今日を含む直近 14 日だけ。15 日前と未来の記録は入れない")
    func onlyRecentDays() {
        let points = [
            WeightPoint(date: day(0), weightKg: 71),   // 今日から 14 日前（入らない）
            WeightPoint(date: day(1), weightKg: 70.9), // 13 日前（入る）
            WeightPoint(date: day(14), weightKg: 70),  // 今日
            WeightPoint(date: day(15), weightKg: 69),  // 明日（入らない）
        ]
        let records = WidgetSnapshotBuilder.recentRecords(points: points, now: day(14, hour: 12), calendar: calendar)
        #expect(records.map(\.date) == [day(1), day(14)])
    }
}
