import Foundation

/// Apple Watch の画面とコンプリケーションに出す内容を、表示する日に合わせてまとめたもの。仕様は docs/WATCH.md。
///
/// 新しい計算はしません。iPhone が作ったスナップショット（ホーム・ウィジェットと同じ数字）を、
/// 「目標まで」「期限まで」「連続記録」の形に並べ直すだけです（日付で変わるものは `WidgetDisplay` で数える）。
nonisolated struct WatchSummary: Equatable, Sendable {
    /// 目標についての出し方
    enum GoalState: Equatable, Sendable {
        /// 目標がない（または iPhone からまだ何も届いていない）
        case noGoal
        /// 目標はあるが、記録がない
        case noRecord
        /// 目標まであと ○ kg。`progress` は 0〜1（出せないときは nil）
        case remaining(kg: Double, progress: Double?)
        /// 目標に届いた
        case achieved
        /// キープモード中（Pro）
        case maintenance(lowerKg: Double, upperKg: Double, isInRange: Bool)
    }

    /// いちばん新しい体重（送信待ちを含む）。記録がなければ nil。
    var latest: LatestWeight?
    var goal: GoalState
    /// 期限までの残り。目標がない・届いた・キープモード中は nil。
    var deadline: WidgetDeadlineStatus?
    /// 連続記録日数（途切れていたら 0）
    var streakDays: Int
    /// 今日の記録があるか（送信待ちを含む）
    var hasRecordedToday: Bool
    /// iPhone からまだ一度もデータが届いていない
    var isWaitingForPhone: Bool

    init(snapshot: WidgetSnapshot?, pending: [WatchWeightRecord], today: Date, calendar: Calendar = .current) {
        latest = WatchDisplay.latest(snapshot: snapshot, pending: pending)
        isWaitingForPhone = snapshot == nil
        streakDays = snapshot.map { WidgetDisplay.visibleStreakDays($0, today: today, calendar: calendar) } ?? 0
        let recordedOnPhone = snapshot.map { WidgetDisplay.hasRecordedToday($0, today: today, calendar: calendar) } ?? false
        hasRecordedToday = recordedOnPhone || pending.contains { calendar.isDate($0.date, inSameDayAs: today) }

        if let maintenance = snapshot?.maintenance {
            goal = .maintenance(lowerKg: maintenance.lowerKg, upperKg: maintenance.upperKg, isInRange: maintenance.isInRange)
            deadline = nil
        } else if let summary = snapshot?.goal {
            if summary.isAchieved {
                goal = .achieved
                deadline = nil
            } else {
                goal = summary.remainingKg.map { .remaining(kg: $0, progress: summary.progress) } ?? .noRecord
                deadline = WidgetDisplay.deadlineStatus(deadline: summary.deadline, today: today, calendar: calendar)
            }
        } else {
            goal = .noGoal
            deadline = nil
        }
    }

    /// 「64.2」のような小数 1 桁の文字
    static func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
