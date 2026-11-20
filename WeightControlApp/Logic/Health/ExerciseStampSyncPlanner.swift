import Foundation

/// 「この日は運動した日」とみなすかどうかのルール。
nonisolated enum ExerciseDayDetector {
    /// エクササイズかワークアウトがこの分数以上なら、運動した日
    static let minimumActiveMinutes = 20
    /// または、歩数がこの数以上なら、運動した日（よく歩いた日もほめたいため）
    static let minimumSteps = 10_000.0

    static func isExerciseDay(_ activity: DailyActivity) -> Bool {
        activity.activeMinutes >= minimumActiveMinutes || activity.steps >= minimumSteps
    }
}

/// アプリに保存済みの運動スタンプ（`ExerciseDay` から必要な値だけを抜き出したもの）。
nonisolated struct ExistingExerciseStamp: Equatable, Sendable {
    let day: Date
    /// ヘルスケアから自動で押したスタンプなら true、自分でタップしたスタンプなら false
    let isFromHealthKit: Bool
    let activeMinutes: Int?
}

/// 運動スタンプに加える変更 1 つ分。
nonisolated enum ExerciseStampChange: Equatable, Sendable {
    /// ヘルスケアのスタンプを新しく押す
    case add(day: Date, activeMinutes: Int)
    /// ヘルスケアのスタンプの運動時間を書き換える
    case updateMinutes(day: Date, activeMinutes: Int)
    /// ヘルスケアのスタンプを外す（運動の記録が消された・減った）
    case remove(day: Date)
}

/// ヘルスケアの運動量から、カレンダーの運動スタンプをどう変えるかを決めます。
///
/// - 自分でタップしたスタンプ（手動）には触りません。手動のスタンプがある日は、自動のスタンプを足しません。
/// - `activities` に含まれる日だけを見ます。含まれない日（同期の対象外の日）のスタンプはそのままです。
nonisolated enum ExerciseStampSyncPlanner {
    static func changes(
        activities: [DailyActivity],
        existing: [ExistingExerciseStamp],
        calendar: Calendar
    ) -> [ExerciseStampChange] {
        let stampsByDay = Dictionary(grouping: existing) { calendar.startOfDay(for: $0.day) }
        var changes: [ExerciseStampChange] = []

        for activity in activities.sorted(by: { $0.day < $1.day }) {
            let day = calendar.startOfDay(for: activity.day)
            let stamps = stampsByDay[day] ?? []
            let hasManual = stamps.contains { !$0.isFromHealthKit }
            let automatic = stamps.first { $0.isFromHealthKit }

            if ExerciseDayDetector.isExerciseDay(activity) {
                if hasManual {
                    continue
                }
                if let automatic {
                    if automatic.activeMinutes != activity.activeMinutes {
                        changes.append(.updateMinutes(day: day, activeMinutes: activity.activeMinutes))
                    }
                } else {
                    changes.append(.add(day: day, activeMinutes: activity.activeMinutes))
                }
            } else if automatic != nil {
                changes.append(.remove(day: day))
            }
        }
        return changes
    }
}
