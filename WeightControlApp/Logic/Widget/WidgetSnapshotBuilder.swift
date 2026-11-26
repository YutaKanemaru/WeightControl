import Foundation

/// ウィジェットに出す数字（`WidgetSnapshot`）を作る係。仕様は docs/WIDGET.md。
///
/// 新しい計算はしません。ホーム画面と同じ数字になるように、`HomeDashboardBuilder` の結果
/// （今の体重の目安・連続記録日数・目標に届いたか・キープモードの判定）をそのまま使い、
/// ウィジェットで使う形に詰め替えるだけです。
nonisolated enum WidgetSnapshotBuilder {
    /// - Parameters:
    ///   - points: 体重の記録（順番はバラバラで OK）
    ///   - goal: 目標。なければ nil。
    ///   - dashboard: 同じ記録と目標で作ったホームの計算結果
    ///   - now: 作る日時
    static func build(
        points: [WeightPoint],
        goal: DashboardGoal?,
        dashboard: HomeDashboard,
        now: Date,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let latest = points.max { $0.date < $1.date }

        let goalSummary = goal.map { goal in
            let startKg = goal.startWeightKg ?? points.min { $0.date < $1.date }?.weightKg
            let currentKg = dashboard.currentWeightKg
            let progress: Double? = {
                guard let startKg, let currentKg else { return nil }
                return HomeDashboardBuilder.goalProgress(startKg: startKg, currentKg: currentKg, targetKg: goal.targetWeightKg)
                    .map { min($0, 1) }
            }()
            return WidgetGoalSummary(
                targetWeightKg: goal.targetWeightKg,
                deadline: goal.deadline,
                // ホームの「目標まで」と同じ：今の体重の目安と目標体重の差
                remainingKg: currentKg.map { abs(goal.targetWeightKg - $0) },
                progress: progress,
                isAchieved: dashboard.isGoalAchieved
            )
        }

        let maintenanceSummary = dashboard.maintenance.map { result in
            WidgetMaintenanceSummary(
                lowerKg: result.range.lowerKg,
                upperKg: result.range.upperKg,
                isInRange: result.range.contains(result.currentWeightKg)
            )
        }

        return WidgetSnapshot(
            generatedAt: now,
            latestWeightKg: latest?.weightKg,
            latestDate: latest?.date,
            recentRecords: recentRecords(points: points, now: now, calendar: calendar),
            streakDays: dashboard.streakDays,
            goal: goalSummary,
            maintenance: maintenanceSummary
        )
    }

    /// 直近 14 日（今日を含む）の記録を、1 日 1 件（その日の最後の記録）にして古い順に並べる。
    /// 未来の日付の記録は入れない。
    static func recentRecords(points: [WeightPoint], now: Date, calendar: Calendar = .current) -> [WidgetWeightRecord] {
        var lastOfDay: [Date: WeightPoint] = [:]
        for point in points {
            let days = DayMath.days(from: point.date, to: now, calendar: calendar)
            guard days >= 0, days < WidgetDisplay.recentDays else { continue }
            let day = calendar.startOfDay(for: point.date)
            if let existing = lastOfDay[day], existing.date > point.date { continue }
            lastOfDay[day] = point
        }
        return lastOfDay.values
            .sorted { $0.date < $1.date }
            .map { WidgetWeightRecord(date: $0.date, weightKg: $0.weightKg) }
    }
}
