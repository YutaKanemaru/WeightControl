import Foundation

/// ウィジェットに出す数字（`WidgetSnapshot`）を作る係。仕様は docs/WIDGET.md。
///
/// 新しい計算はしません。ホーム画面と同じ数字になるように、ホームと同じロジックを使って詰め替えるだけです。
/// - 「目標まで」と「達成」：ホームの体重のカードと同じく、最新の体重から `GoalDistanceCalculator` で出す（docs/WEIGHT_RECORDS.md）
/// - 進み具合・連続記録日数・キープモード：`HomeDashboardBuilder` の結果（進み具合は今の体重の目安から）
/// - グラフ：ホームのグラフと同じく、同じ日の記録は平均して 1 日 1 点
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
            // ホームの「目標まで」と同じ：最新の体重と目標体重の差。0.1 kg 以内か、通りこしたら「達成」
            let distance = latest.map {
                GoalDistanceCalculator.distance(latestKg: $0.weightKg, targetKg: goal.targetWeightKg, startKg: startKg)
            }
            let remainingKg: Double? = {
                if case .toGo(let kg) = distance { return kg }
                return nil
            }()
            let isAchieved: Bool = {
                switch distance {
                case .reached, .beyond: return true
                case .toGo, nil: return false
                }
            }()
            let progress: Double? = {
                guard let startKg, let currentKg else { return nil }
                return HomeDashboardBuilder.goalProgress(startKg: startKg, currentKg: currentKg, targetKg: goal.targetWeightKg)
                    .map { min($0, 1) }
            }()
            return WidgetGoalSummary(
                targetWeightKg: goal.targetWeightKg,
                deadline: goal.deadline,
                remainingKg: remainingKg,
                progress: isAchieved ? 1 : progress,
                isAchieved: isAchieved
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

    /// 直近 14 日（今日を含む）の記録を、1 日 1 件（同じ日の記録は平均。日付はその日の 0 時）にして古い順に並べる。
    /// 未来の日付の記録は入れない。
    static func recentRecords(points: [WeightPoint], now: Date, calendar: Calendar = .current) -> [WidgetWeightRecord] {
        let recent = points.filter {
            let days = DayMath.days(from: $0.date, to: now, calendar: calendar)
            return days >= 0 && days < WidgetDisplay.recentDays
        }
        return WeightTrendCalculator.dailyAverages(recent, calendar: calendar)
            .sorted { $0.date < $1.date }
            .map { WidgetWeightRecord(date: $0.date, weightKg: $0.weightKg) }
    }
}
