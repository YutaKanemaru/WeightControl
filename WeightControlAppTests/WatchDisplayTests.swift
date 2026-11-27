import Foundation
import Testing
@testable import WeightControlApp

/// Apple Watch の表示と記録のルール（Shared/WatchDisplay・WatchSummary・WatchMessage・WatchPendingStore）のテスト。
struct WatchDisplayTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int, hour: Int = 0) -> Date { TestCalendar.day(n, hour: hour) }

    private func snapshot(
        latestKg: Double? = 64.2,
        latest: Date? = TestCalendar.day(0, hour: 7),
        streak: Int = 5,
        goal: WidgetGoalSummary? = nil,
        maintenance: WidgetMaintenanceSummary? = nil
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: day(0),
            latestWeightKg: latestKg,
            latestDate: latest,
            recentRecords: [],
            streakDays: streak,
            goal: goal,
            maintenance: maintenance
        )
    }

    private func goal(remainingKg: Double?, progress: Double? = 0.4, achieved: Bool = false, deadline: Date = TestCalendar.day(10)) -> WidgetGoalSummary {
        WidgetGoalSummary(targetWeightKg: 61, deadline: deadline, remainingKg: remainingKg, progress: progress, isAchieved: achieved)
    }

    // MARK: - iPhone と同じ決まり

    @Test("範囲・刻み・確認の幅は iPhone の入力画面と同じ")
    func matchesPhoneRules() {
        #expect(WatchDisplay.validRangeKg == WeightInputParser.validRangeKg)
        #expect(WatchDisplay.stepKg == WeightEntryStepper.stepKg)
        #expect(WatchDisplay.largeChangeThresholdKg == WeightEntryCheck.largeChangeThresholdKg)
        for (newKg, previousKg) in [(66.2, 64.2), (62.3, 64.2), (64.0, 64.2), (66.1, 64.2), (64.2, nil)] as [(Double, Double?)] {
            #expect(WatchDisplay.largeChange(newKg: newKg, previousKg: previousKg) == WeightEntryCheck.largeChange(newKg: newKg, previousKg: previousKg))
        }
    }

    @Test("Digital Crown の値は小数第 1 位に丸めて、範囲におさめる")
    func roundsCrownValue() {
        #expect(WatchDisplay.rounded(64.30000001) == 64.3)
        #expect(WatchDisplay.rounded(64.249) == 64.2)
        #expect(WatchDisplay.rounded(10) == 20)
        #expect(WatchDisplay.rounded(400) == 300)
    }

    @Test("記録の画面は、いちばん新しい記録（送信待ちを含む）から始める")
    func startWeight() {
        #expect(WatchDisplay.startWeightKg(snapshot: snapshot(), pending: []) == 64.2)
        let pending = [WatchWeightRecord(id: UUID(), date: day(1, hour: 7), weightKg: 63.9)]
        #expect(WatchDisplay.startWeightKg(snapshot: snapshot(), pending: pending) == 63.9)
        #expect(WatchDisplay.startWeightKg(snapshot: nil, pending: []) == WatchDisplay.defaultStartKg)
    }

    // MARK: - 送信待ち

    @Test("最新の体重は、iPhone の記録と送信待ちのうち新しいほう")
    func latestWeight() {
        let newer = WatchWeightRecord(id: UUID(), date: day(1, hour: 7), weightKg: 63.9)
        let older = WatchWeightRecord(id: UUID(), date: day(0, hour: 6), weightKg: 64.5)
        #expect(WatchDisplay.latest(snapshot: snapshot(), pending: [newer]) == LatestWeight(weightKg: 63.9, date: day(1, hour: 7), isPending: true))
        #expect(WatchDisplay.latest(snapshot: snapshot(), pending: [older]) == LatestWeight(weightKg: 64.2, date: day(0, hour: 7), isPending: false))
        #expect(WatchDisplay.latest(snapshot: nil, pending: [older])?.isPending == true)
        #expect(WatchDisplay.latest(snapshot: snapshot(latestKg: nil, latest: nil), pending: []) == nil)
    }

    @Test("受け取り済みの ID と、7 日より古い送信待ちを外す")
    func remainingPending() {
        let acknowledged = WatchWeightRecord(id: UUID(), date: day(10), weightKg: 64)
        let waiting = WatchWeightRecord(id: UUID(), date: day(10), weightKg: 64)
        let tooOld = WatchWeightRecord(id: UUID(), date: day(2, hour: 23), weightKg: 64)
        let result = WatchDisplay.remainingPending(
            [tooOld, acknowledged, waiting],
            acknowledgedIDs: [acknowledged.id],
            now: day(10),
            calendar: calendar
        )
        #expect(result == [waiting])
    }

    // MARK: - 画面とコンプリケーションの内容

    @Test("目標まで ○ kg と期限まで ○ 日")
    func summaryRemaining() {
        let summary = WatchSummary(snapshot: snapshot(goal: goal(remainingKg: 3.2)), pending: [], today: day(0, hour: 20), calendar: calendar)
        #expect(summary.goal == .remaining(kg: 3.2, progress: 0.4))
        #expect(summary.deadline == .daysLeft(10))
        #expect(summary.streakDays == 5)
        #expect(summary.hasRecordedToday)
        #expect(!summary.isWaitingForPhone)
    }

    @Test("届いたら「達成」で、期限は出さない")
    func summaryAchieved() {
        let summary = WatchSummary(snapshot: snapshot(goal: goal(remainingKg: nil, achieved: true)), pending: [], today: day(0), calendar: calendar)
        #expect(summary.goal == .achieved)
        #expect(summary.deadline == nil)
    }

    @Test("キープモード中は範囲を出し、期限は出さない")
    func summaryMaintenance() {
        let summary = WatchSummary(
            snapshot: snapshot(goal: goal(remainingKg: 1), maintenance: WidgetMaintenanceSummary(lowerKg: 59.5, upperKg: 62.5, isInRange: true)),
            pending: [],
            today: day(0),
            calendar: calendar
        )
        #expect(summary.goal == .maintenance(lowerKg: 59.5, upperKg: 62.5, isInRange: true))
        #expect(summary.deadline == nil)
    }

    @Test("目標がない・記録がない・iPhone からまだ届いていない")
    func summaryEmpty() {
        #expect(WatchSummary(snapshot: snapshot(), pending: [], today: day(0), calendar: calendar).goal == .noGoal)
        let noRecord = WatchSummary(snapshot: snapshot(latestKg: nil, latest: nil, goal: goal(remainingKg: nil)), pending: [], today: day(0), calendar: calendar)
        #expect(noRecord.goal == .noRecord)
        #expect(noRecord.latest == nil)
        let waiting = WatchSummary(snapshot: nil, pending: [], today: day(0), calendar: calendar)
        #expect(waiting.isWaitingForPhone)
        #expect(waiting.goal == .noGoal)
        #expect(waiting.streakDays == 0)
    }

    @Test("連続記録は途切れていたら 0、今日の記録は送信待ちも数える")
    func summaryStreak() {
        let broken = WatchSummary(snapshot: snapshot(), pending: [], today: day(3), calendar: calendar)
        #expect(broken.streakDays == 0)
        #expect(!broken.hasRecordedToday)
        let pending = [WatchWeightRecord(id: UUID(), date: day(1, hour: 7), weightKg: 64)]
        let recorded = WatchSummary(snapshot: snapshot(), pending: pending, today: day(1, hour: 9), calendar: calendar)
        #expect(recorded.hasRecordedToday)
        #expect(recorded.streakDays == 5)
        #expect(recorded.latest?.isPending == true)
    }

    // MARK: - やりとりする辞書と保存

    @Test("記録とスナップショットは、詰めて取り出すと元にもどる")
    func messageRoundTrip() {
        let record = WatchWeightRecord(id: UUID(), date: day(0, hour: 7), weightKg: 64.2)
        #expect(WatchMessage.record(from: WatchMessage.payload(for: record)) == record)

        let original = snapshot(goal: goal(remainingKg: 3.2))
        let ids = [UUID(), UUID()]
        let payload = WatchMessage.payload(snapshot: original, acknowledgedIDs: ids)
        #expect(WatchMessage.snapshot(from: payload) == original)
        #expect(WatchMessage.acknowledgedIDs(from: payload) == Set(ids))

        let empty = WatchMessage.payload(snapshot: nil, acknowledgedIDs: [])
        #expect(WatchMessage.snapshot(from: empty) == nil)
        #expect(WatchMessage.record(from: [:]) == nil)
    }

    @Test("送信待ちは保存して読み直せる")
    func pendingStore() {
        let suite = "WatchDisplayTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = WatchPendingStore(suiteName: suite)
        #expect(store.load().isEmpty)
        let records = [WatchWeightRecord(id: UUID(), date: day(0), weightKg: 64.2)]
        store.save(records)
        #expect(store.load() == records)
    }
}
