import Foundation
import SwiftData
import WidgetKit

/// ウィジェットと Apple Watch に出す数字（`WidgetSnapshot`）を作って届ける係。
///
/// - ウィジェット：App Group に保存して、`WidgetCenter`（WidgetKit の窓口）の `reloadAllTimelines()` で「描き直して」と知らせる。
///   iPhone がウィジェットの拡張を動かして、新しい表示の予定表（タイムライン）を受け取り直します。
///   描き直しは iPhone の都合で少し遅れることがありますが、アプリが前面にあるときはすぐに反映されます。
/// - Apple Watch：`WatchSyncService` が WatchConnectivity で同じスナップショットを送ります（docs/WATCH.md）。
enum WidgetSnapshotPublisher {
    private static let store = WidgetSnapshotStore()

    /// 保存されている記録と目標からスナップショットを作って届ける。
    ///
    /// 画面（`WidgetSnapshotSync`）からも、Watch から記録が届いたとき（アプリが裏で起こされて画面がないとき）からも呼べるように、
    /// `@Query` ではなく `ModelContext` から読みます。
    @discardableResult
    static func publish(context: ModelContext, isProUnlocked: Bool, now: Date = .now) -> WidgetSnapshot {
        let entries = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        // 目標は 1 件だけの想定。念のため新しい順に並べて先頭を使う
        let goals = (try? context.fetch(FetchDescriptor<WeightGoal>(sortBy: [SortDescriptor(\.startDate, order: .reverse)]))) ?? []
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []

        let points = entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) }
        let goal = goals.first?.dashboardGoal(includesMaintenance: isProUnlocked)
        // ホームと同じ計算で「今の体重の目安」などを出す（食べ物ヒントや運動量は使わないので渡さない）
        let dashboard = HomeDashboardBuilder.build(
            points: points,
            profile: profiles.first?.dashboardProfile,
            goal: goal,
            foods: [],
            includesPro: isProUnlocked,
            now: now
        )
        let snapshot = WidgetSnapshotBuilder.build(points: points, goal: goal, dashboard: dashboard, now: now)
        publish(snapshot)
        return snapshot
    }

    /// スナップショットを保存して届ける。前に保存したものと同じなら、何もしない（描き直しや送信の回数を減らすため）。
    static func publish(_ snapshot: WidgetSnapshot) {
        if let saved = store.load(), saved.isSameContent(as: snapshot) { return }
        store.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        WatchSyncService.shared?.sendSnapshot(snapshot)
    }

    /// 最後に保存したスナップショット（Watch とつながったときに、まず送る用）
    static var latest: WidgetSnapshot? {
        store.load()
    }
}

private extension WidgetSnapshot {
    /// 作った日時以外が同じか
    func isSameContent(as other: WidgetSnapshot) -> Bool {
        var copy = other
        copy.generatedAt = generatedAt
        return copy == self
    }
}
