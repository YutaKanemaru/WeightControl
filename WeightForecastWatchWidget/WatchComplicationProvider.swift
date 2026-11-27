import Foundation
import WidgetKit

/// タイムラインの 1 コマ：「この時刻になったら、この内容で描く」
struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let summary: WatchSummary
}

/// コンプリケーションの表示の予定表（タイムライン）を渡す係。
///
/// 計算はせず、Watch アプリが Watch の App Group に保存したスナップショットと送信待ちを読むだけです。
/// 「期限まで」「連続記録」は日付で変わるので、「今」と「次の 0 時」の 2 コマを渡します（iPhone のウィジェットと同じ）。
struct WatchComplicationProvider: TimelineProvider {
    private let snapshotStore = WidgetSnapshotStore()
    private let pendingStore = WatchPendingStore()

    func placeholder(in context: Context) -> WatchComplicationEntry {
        entry(date: .now, snapshot: .complicationSample, pending: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        // 文字盤の編集画面の見本では、データがなければ見本の数字を出す
        let snapshot = snapshotStore.load() ?? (context.isPreview ? .complicationSample : nil)
        completion(entry(date: .now, snapshot: snapshot, pending: pendingStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        let now = Date.now
        let snapshot = snapshotStore.load()
        let pending = pendingStore.load()
        let entries = [
            entry(date: now, snapshot: snapshot, pending: pending),
            entry(date: WidgetDisplay.nextRefreshDate(after: now), snapshot: snapshot, pending: pending),
        ]
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(date: Date, snapshot: WidgetSnapshot?, pending: [WatchWeightRecord]) -> WatchComplicationEntry {
        WatchComplicationEntry(date: date, summary: WatchSummary(snapshot: snapshot, pending: pending, today: date))
    }
}

extension WidgetSnapshot {
    /// 文字盤の編集画面に出す見本（本当の記録ではない、決まった数字）
    static var complicationSample: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return WidgetSnapshot(
            generatedAt: .now,
            latestWeightKg: 64.2,
            latestDate: today.addingTimeInterval(7 * 3_600),
            recentRecords: [],
            streakDays: 12,
            goal: WidgetGoalSummary(
                targetWeightKg: 61,
                deadline: calendar.date(byAdding: .day, value: 45, to: today) ?? today,
                remainingKg: 3.2,
                progress: 0.45,
                isAchieved: false
            ),
            maintenance: nil
        )
    }
}
