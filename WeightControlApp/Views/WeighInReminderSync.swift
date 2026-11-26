import SwiftUI
import SwiftData

/// 記録や設定が変わったら、リマインド通知とほめる通知を自動で作り直す仕組み（ViewModifier）。
///
/// `ViewModifier` は「画面に後から機能を足す部品」です。`RootView` に 1 行付けておくだけで、
/// どの画面で記録を追加・削除しても、ここが変化に気づいて通知を作り直します。
/// こうしておくと、記録画面や履歴画面に通知のコードを書かずにすみます。
struct WeighInReminderSync: ViewModifier {
    @Query private var entries: [WeightEntry]
    /// 目標は 1 件だけの想定。念のため新しい順に並べて先頭を使う（ほめる通知の「目標の節目」に使う）
    @Query(sort: \WeightGoal.startDate, order: .reverse) private var goals: [WeightGoal]
    /// 身長（キープモードの範囲をホームと同じにするため）
    @Query private var profiles: [UserProfile]
    /// Pro を使えるか（使えないときは、キープモードのお知らせを出さない）
    @Environment(ProAccess.self) private var pro: ProAccess?
    /// アプリが前面にあるか、裏に回ったか（scenePhase）。前面に戻るたびに日付が変わっている可能性があるので作り直す
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(ReminderPreferenceKey.isEnabled) private var isEnabled = false
    @AppStorage(ReminderPreferenceKey.hour) private var hour = ReminderTime.defaultTime.hour
    @AppStorage(ReminderPreferenceKey.minute) private var minute = ReminderTime.defaultTime.minute
    @AppStorage(PraiseNotificationPreferenceKey.isEnabled) private var isPraiseEnabled = false

    /// これらのどれかが変わったら作り直す
    private struct Trigger: Equatable {
        var points: [WeightPoint]
        var goal: DashboardGoal?
        var isEnabled: Bool
        var hour: Int
        var minute: Int
        var isPraiseEnabled: Bool
        var isActive: Bool
        var heightCm: Double?
    }

    /// 記録を計算用の値（`WeightPoint`）に詰め替えたもの
    private var points: [WeightPoint] {
        entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) }
    }

    /// ほめる通知に渡す目標。Pro を使えないときは、キープモードの情報を外す
    private var praiseGoal: DashboardGoal? {
        goals.first?.dashboardGoal(includesMaintenance: pro?.isUnlocked ?? false)
    }

    func body(content: Content) -> some View {
        content
            // .task(id:) は、画面が表示されたときと、id の値が変わったときに中身を実行します
            .task(id: Trigger(points: points,
                              goal: praiseGoal,
                              isEnabled: isEnabled,
                              hour: hour,
                              minute: minute,
                              isPraiseEnabled: isPraiseEnabled,
                              isActive: scenePhase == .active,
                              heightCm: profiles.first?.heightCm)) {
                let points = points
                WeighInReminderScheduler.shared.update(
                    isEnabled: isEnabled,
                    time: ReminderTime(hour: hour, minute: minute),
                    recordedDates: points.map(\.date)
                )
                PraiseNotificationScheduler.shared.update(
                    isEnabled: isPraiseEnabled,
                    points: points,
                    goal: praiseGoal,
                    heightCm: profiles.first?.heightCm
                )
            }
    }
}

extension View {
    /// 記録や設定の変化にあわせて、リマインド通知とほめる通知を作り直します。
    func weighInReminderSync() -> some View {
        modifier(WeighInReminderSync())
    }
}
