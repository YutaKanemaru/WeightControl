import Foundation
import Testing
@testable import WeightControlApp

/// ウィジェットを描く日に合わせた表示のルール（Shared/WidgetDisplay）と、保存（WidgetSnapshotStore）のテスト。
struct WidgetDisplayTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int, hour: Int = 0) -> Date { TestCalendar.day(n, hour: hour) }

    private func snapshot(latest: Date?, streak: Int = 5, records: [WidgetWeightRecord] = []) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: day(0),
            latestWeightKg: latest == nil ? nil : 64.2,
            latestDate: latest,
            recentRecords: records,
            streakDays: streak,
            goal: nil,
            maintenance: nil
        )
    }

    // MARK: - 期限まで

    @Test("期限まで何日かは日付だけで数える（時刻は見ない）")
    func deadlineDays() {
        #expect(WidgetDisplay.deadlineStatus(deadline: day(10), today: day(0, hour: 23), calendar: calendar) == .daysLeft(10))
        #expect(WidgetDisplay.deadlineStatus(deadline: day(1, hour: 1), today: day(0, hour: 23), calendar: calendar) == .daysLeft(1))
    }

    @Test("期限の日は「今日」、過ぎたら「過ぎた」")
    func deadlineTodayAndPassed() {
        #expect(WidgetDisplay.deadlineStatus(deadline: day(3), today: day(3, hour: 20), calendar: calendar) == .today)
        #expect(WidgetDisplay.deadlineStatus(deadline: day(3), today: day(4), calendar: calendar) == .passed)
    }

    // MARK: - 今日の記録・連続記録日数

    @Test("今日の記録があるか")
    func recordedToday() {
        #expect(WidgetDisplay.hasRecordedToday(snapshot(latest: day(2, hour: 7)), today: day(2, hour: 22), calendar: calendar))
        #expect(!WidgetDisplay.hasRecordedToday(snapshot(latest: day(1, hour: 7)), today: day(2, hour: 1), calendar: calendar))
        #expect(!WidgetDisplay.hasRecordedToday(snapshot(latest: nil), today: day(2), calendar: calendar))
    }

    @Test("連続記録日数は、最新の記録が今日か昨日なら出し、それより前なら 0")
    func streak() {
        #expect(WidgetDisplay.visibleStreakDays(snapshot(latest: day(2, hour: 7)), today: day(2, hour: 9), calendar: calendar) == 5)
        #expect(WidgetDisplay.visibleStreakDays(snapshot(latest: day(1, hour: 7)), today: day(2, hour: 9), calendar: calendar) == 5)
        #expect(WidgetDisplay.visibleStreakDays(snapshot(latest: day(0, hour: 7)), today: day(2, hour: 9), calendar: calendar) == 0)
        #expect(WidgetDisplay.visibleStreakDays(snapshot(latest: nil), today: day(2), calendar: calendar) == 0)
    }

    @Test("グラフには、表示する日から数えて直近 14 日の記録だけを出す")
    func visibleRecords() {
        let records = [
            WidgetWeightRecord(date: day(0), weightKg: 70),
            WidgetWeightRecord(date: day(5), weightKg: 69.5),
            WidgetWeightRecord(date: day(13), weightKg: 69),
        ]
        // 2 日たってから表示すると、day(0) は 15 日前になるので外す
        let visible = WidgetDisplay.visibleRecords(snapshot(latest: day(13), records: records), today: day(15), calendar: calendar)
        #expect(visible.map(\.date) == [day(5), day(13)])
    }

    @Test("次に描き直すのは次の日の 0 時")
    func nextRefresh() {
        #expect(WidgetDisplay.nextRefreshDate(after: day(3, hour: 15), calendar: calendar) == day(4))
        #expect(WidgetDisplay.nextRefreshDate(after: day(3), calendar: calendar) == day(4))
    }

    // MARK: - 保存

    @Test("保存したスナップショットをそのまま読み戻せる")
    func storeRoundTrip() throws {
        let suiteName = "WidgetDisplayTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(suiteName: suiteName)
        #expect(store.load() == nil)

        var value = snapshot(latest: day(2, hour: 7), records: [WidgetWeightRecord(date: day(2, hour: 7), weightKg: 64.2)])
        value.goal = WidgetGoalSummary(targetWeightKg: 62, deadline: day(60), remainingKg: 2.1, progress: 0.4, isAchieved: false)
        value.maintenance = WidgetMaintenanceSummary(lowerKg: 60.5, upperKg: 63.5, isInRange: true)
        store.save(value)
        #expect(store.load() == value)
    }

    @Test("形の版が違うデータは読まない")
    func storeIgnoresOtherVersion() throws {
        let suiteName = "WidgetDisplayTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(suiteName: suiteName)
        var value = snapshot(latest: day(2))
        value.version = WidgetSnapshot.currentVersion + 1
        store.save(value)
        #expect(store.load() == nil)
    }
}
