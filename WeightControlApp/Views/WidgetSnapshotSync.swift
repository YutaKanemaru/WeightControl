import SwiftUI
import SwiftData

/// 記録や目標が変わったら、ウィジェットに出す数字を作り直す仕組み（ViewModifier）。仕様は docs/WIDGET.md。
///
/// `WeighInReminderSync` と同じく、`RootView` に 1 行付けておくだけで、どの画面で記録を追加・削除しても、
/// ここが変化に気づいてウィジェットを更新します。ヘルスケアから体重を取り込んだときも、記録が増えるので更新されます。
struct WidgetSnapshotSync: ViewModifier {
    @Query private var entries: [WeightEntry]
    /// 目標は 1 件だけの想定。念のため新しい順に並べて先頭を使う
    @Query(sort: \WeightGoal.startDate, order: .reverse) private var goals: [WeightGoal]
    /// 身長（キープモードの範囲の下の端を、ホームと同じにするため）
    @Query private var profiles: [UserProfile]
    /// Pro を使えるか（使えないときは、キープモードの範囲を出さない）
    @Environment(ProAccess.self) private var pro: ProAccess?
    /// 前面に戻るたびに日付が変わっている可能性があるので作り直す
    @Environment(\.scenePhase) private var scenePhase

    /// これらのどれかが変わったら作り直す
    private struct Trigger: Equatable {
        var points: [WeightPoint]
        var goal: DashboardGoal?
        var profile: DashboardProfile?
        var isProUnlocked: Bool
        var isActive: Bool
    }

    private var points: [WeightPoint] {
        entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) }
    }

    func body(content: Content) -> some View {
        let isProUnlocked = pro?.isUnlocked ?? false
        let goal = goals.first?.dashboardGoal(includesMaintenance: isProUnlocked)
        let profile = profiles.first?.dashboardProfile
        return content
            .task(id: Trigger(points: points, goal: goal, profile: profile, isProUnlocked: isProUnlocked, isActive: scenePhase == .active)) {
                let points = points
                let now = Date.now
                // ホームと同じ計算で「今の体重の目安」などを出す（食べ物ヒントや運動量は使わないので渡さない）
                let dashboard = HomeDashboardBuilder.build(
                    points: points,
                    profile: profile,
                    goal: goal,
                    foods: [],
                    includesPro: isProUnlocked,
                    now: now
                )
                let snapshot = WidgetSnapshotBuilder.build(points: points, goal: goal, dashboard: dashboard, now: now)
                WidgetSnapshotPublisher.publish(snapshot)
            }
    }
}

extension View {
    /// 記録や目標の変化にあわせて、ウィジェットの表示を更新します。
    func widgetSnapshotSync() -> some View {
        modifier(WidgetSnapshotSync())
    }
}
