import Foundation
import SwiftUI
import WidgetKit

/// タイムラインの 1 コマ：「この時刻になったら、このスナップショットで描く」
struct WeightSummaryEntry: TimelineEntry {
    /// 表示を切り替える時刻（「期限まで ○ 日」などはこの日で数える）
    let date: Date
    /// アプリが書いた、ウィジェットに出す数字
    let snapshot: WidgetSnapshot
}

/// ウィジェットの表示の予定表（タイムライン）を iPhone に渡す係。
///
/// iPhone はウィジェットを描くときにここを呼びます。ここでは計算をせず、
/// アプリが App Group に保存したスナップショットを読むだけにしています（docs/WIDGET.md の「しくみ」）。
struct WeightSummaryProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    /// まだ読み込む前の仮の表示（形だけ見せる。数字は伏せ字のように描かれる）
    func placeholder(in context: Context) -> WeightSummaryEntry {
        WeightSummaryEntry(date: .now, snapshot: .sample)
    }

    /// ウィジェットの一覧（追加する前の見本）では見本の数字、置いたあとは本当の数字
    func getSnapshot(in context: Context, completion: @escaping (WeightSummaryEntry) -> Void) {
        let snapshot = context.isPreview ? (store.load() ?? .sample) : (store.load() ?? .empty())
        completion(WeightSummaryEntry(date: .now, snapshot: snapshot))
    }

    /// 「今」と「次の 0 時」の 2 コマを渡す。0 時を過ぎたら（`.atEnd`）、もう一度ここを呼んでもらう。
    /// 記録や目標が変わったときは、アプリが `WidgetCenter` で描き直しを頼むので、すぐに新しい数字になる。
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeightSummaryEntry>) -> Void) {
        let now = Date.now
        let snapshot = store.load() ?? .empty()
        let entries = [
            WeightSummaryEntry(date: now, snapshot: snapshot),
            WeightSummaryEntry(date: WidgetDisplay.nextRefreshDate(after: now), snapshot: snapshot),
        ]
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// 体重のウィジェット（ホーム画面の小・中、ロック画面の長方形・丸・1 行）
struct WeightSummaryWidget: Widget {
    let kind = "WeightSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeightSummaryProvider()) { entry in
            WeightSummaryWidgetView(entry: entry)
                // ウィジェットの背景。システムの色にしておくと、ダークモードや色合いの設定に自動で合う
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("体重と目標")
        .description("最新の体重と、目標まであと何 kg・期限まであと何日かを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

extension WidgetSnapshot {
    /// ウィジェットの一覧に出す見本（本当の記録ではない、決まった数字）
    static var sample: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weights = [65.4, 65.3, 65.4, 65.1, 65.0, 65.1, 64.8, 64.9, 64.7, 64.6, 64.7, 64.4, 64.3, 64.2]
        let records = weights.enumerated().compactMap { index, kg -> WidgetWeightRecord? in
            guard let date = calendar.date(byAdding: .day, value: index - (weights.count - 1), to: today) else { return nil }
            return WidgetWeightRecord(date: date.addingTimeInterval(7 * 3_600), weightKg: kg)
        }
        return WidgetSnapshot(
            generatedAt: .now,
            latestWeightKg: 64.2,
            latestDate: records.last?.date,
            recentRecords: records,
            streakDays: 14,
            goal: WidgetGoalSummary(
                targetWeightKg: 62,
                deadline: calendar.date(byAdding: .day, value: 48, to: today) ?? today,
                remainingKg: 2.2,
                progress: 0.45,
                isAchieved: false
            ),
            maintenance: nil
        )
    }
}
