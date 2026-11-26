import Foundation
import Charts
import SwiftUI
import WidgetKit

/// ウィジェットに出す内容を、表示する日に合わせてまとめたもの（各サイズの画面で共通に使う）。
struct WeightSummaryContent {
    /// 目標についての 1 行の出し方
    enum GoalLine {
        /// 目標がない
        case none
        /// 目標まであと ○ kg
        case remaining(kg: Double)
        /// 目標に届いている
        case achieved
        /// キープモード中（Pro）
        case maintenance(lowerKg: Double, upperKg: Double, isInRange: Bool)
    }

    let latestKg: Double?
    let goalLine: GoalLine
    /// 期限までの残り。目標がない・届いた・キープモード中は nil。
    let deadline: WidgetDeadlineStatus?
    /// 目標までの進み具合（0〜1）。出さないときは nil。
    let progress: Double?
    let hasRecordedToday: Bool
    let streakDays: Int
    let records: [WidgetWeightRecord]
    /// グラフに描く目標の横線（記録の近くにあるときだけ）
    let chartGoalKg: Double?

    init(entry: WeightSummaryEntry, calendar: Calendar = .current) {
        let snapshot = entry.snapshot
        let today = entry.date
        latestKg = snapshot.latestWeightKg
        hasRecordedToday = WidgetDisplay.hasRecordedToday(snapshot, today: today, calendar: calendar)
        streakDays = WidgetDisplay.visibleStreakDays(snapshot, today: today, calendar: calendar)
        records = WidgetDisplay.visibleRecords(snapshot, today: today, calendar: calendar)

        if let maintenance = snapshot.maintenance {
            goalLine = .maintenance(lowerKg: maintenance.lowerKg, upperKg: maintenance.upperKg, isInRange: maintenance.isInRange)
            deadline = nil
            progress = nil
        } else if let goal = snapshot.goal {
            if goal.isAchieved {
                goalLine = .achieved
                deadline = nil
            } else {
                goalLine = goal.remainingKg.map { .remaining(kg: $0) } ?? .none
                deadline = WidgetDisplay.deadlineStatus(deadline: goal.deadline, today: today, calendar: calendar)
            }
            progress = goal.isAchieved ? 1 : goal.progress
        } else {
            goalLine = .none
            deadline = nil
            progress = nil
        }

        // 目標が記録から 2 kg より離れていたら、グラフが平たくなるので横線は描かない
        if let target = snapshot.goal?.targetWeightKg, snapshot.maintenance == nil,
           let low = records.map(\.weightKg).min(), let high = records.map(\.weightKg).max(),
           target >= low - 2, target <= high + 2 {
            chartGoalKg = target
        } else {
            chartGoalKg = nil
        }
    }

    /// 「64.2」のような小数 1 桁の文字
    static func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

/// ウィジェットの大きさに合わせて、出す画面を切りかえる
struct WeightSummaryWidgetView: View {
    let entry: WeightSummaryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let content = WeightSummaryContent(entry: entry)
        switch family {
        case .systemMedium:
            MediumWeightView(content: content)
        case .accessoryRectangular:
            RectangularWeightView(content: content)
        case .accessoryCircular:
            CircularWeightView(content: content)
        case .accessoryInline:
            InlineWeightView(content: content)
        default:
            SmallWeightView(content: content)
        }
    }
}

// MARK: - ホーム画面：小

struct SmallWeightView: View {
    let content: WeightSummaryContent

    var body: some View {
        if let latestKg = content.latestKg {
            VStack(alignment: .leading, spacing: 4) {
                Label("体重", systemImage: "scalemass.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                LatestWeightText(kg: latestKg)
                Spacer(minLength: 0)
                GoalSummaryRows(content: content)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyWeightView()
        }
    }
}

// MARK: - ホーム画面：中

struct MediumWeightView: View {
    let content: WeightSummaryContent

    var body: some View {
        if content.latestKg == nil {
            EmptyWeightView()
        } else {
            HStack(alignment: .top, spacing: 16) {
                SmallWeightView(content: content)
                VStack(alignment: .leading, spacing: 6) {
                    RecentRecordsChart(records: content.records, goalKg: content.chartGoalKg)
                    TodayStatusRow(hasRecordedToday: content.hasRecordedToday, streakDays: content.streakDays)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 直近 14 日の記録の小さなグラフ（点と線。目標が近ければ点線の横線）
struct RecentRecordsChart: View {
    let records: [WidgetWeightRecord]
    let goalKg: Double?

    var body: some View {
        if records.count >= 2 {
            let values = records.map(\.weightKg) + [goalKg].compactMap { $0 }
            let low = (values.min() ?? 0) - 0.3
            let high = (values.max() ?? 0) + 0.3
            Chart {
                if let goalKg {
                    RuleMark(y: .value("目標", goalKg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary)
                }
                ForEach(records, id: \.date) { record in
                    LineMark(x: .value("日付", record.date), y: .value("体重", record.weightKg))
                        .foregroundStyle(.tint)
                    PointMark(x: .value("日付", record.date), y: .value("体重", record.weightKg))
                        .symbolSize(16)
                        .foregroundStyle(.tint)
                }
            }
            .chartYScale(domain: low...high)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .privacySensitive()
            .accessibilityLabel("直近 14 日の体重のグラフ")
        } else {
            Text("記録が増えるとグラフが出ます")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 今日の記録と連続記録日数の 1 行
struct TodayStatusRow: View {
    let hasRecordedToday: Bool
    let streakDays: Int

    var body: some View {
        HStack(spacing: 8) {
            if hasRecordedToday {
                Label("今日は記録ずみ", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("今日はまだ", systemImage: "circle")
                    .foregroundStyle(.secondary)
            }
            if streakDays >= 2 {
                Text("\(streakDays) 日連続")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - ロック画面

struct RectangularWeightView: View {
    let content: WeightSummaryContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let latestKg = content.latestKg {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Image(systemName: "scalemass.fill")
                        .font(.caption)
                    Text(WeightSummaryContent.kg(latestKg))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .privacySensitive()
                        .widgetAccentable()
                    Text("kg")
                        .font(.caption)
                }
                GoalLineText(goalLine: content.goalLine)
                    .font(.caption)
                if let deadline = content.deadline {
                    DeadlineText(status: deadline)
                        .font(.caption)
                }
            } else {
                Label("体重を記録しましょう", systemImage: "scalemass")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CircularWeightView: View {
    let content: WeightSummaryContent

    var body: some View {
        if let progress = content.progress, case .remaining(let kg) = content.goalLine {
            // 目標までの進み具合のメーター。まん中に残りの kg
            Gauge(value: min(max(progress, 0), 1)) {
                Image(systemName: "flag.fill")
            } currentValueLabel: {
                Text(WeightSummaryContent.kg(kg))
                    .monospacedDigit()
                    .privacySensitive()
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
            .accessibilityLabel("目標まで \(WeightSummaryContent.kg(kg)) kg")
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    if case .achieved = content.goalLine {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                    }
                    if let latestKg = content.latestKg {
                        Text(WeightSummaryContent.kg(latestKg))
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .privacySensitive()
                        Text("kg")
                            .font(.caption2)
                    } else {
                        Image(systemName: "scalemass")
                    }
                }
            }
        }
    }
}

struct InlineWeightView: View {
    let content: WeightSummaryContent

    var body: some View {
        if let latestKg = content.latestKg {
            switch content.goalLine {
            case .remaining(let kg):
                Text("\(WeightSummaryContent.kg(latestKg)) kg・目標まで \(WeightSummaryContent.kg(kg)) kg")
                    .privacySensitive()
            case .achieved:
                Text("\(WeightSummaryContent.kg(latestKg)) kg・目標に届いています")
                    .privacySensitive()
            case .maintenance, .none:
                Label("\(WeightSummaryContent.kg(latestKg)) kg", systemImage: "scalemass.fill")
                    .privacySensitive()
            }
        } else {
            Label("体重を記録しましょう", systemImage: "scalemass")
        }
    }
}

// MARK: - 共通の部品

/// 最新の体重を大きく太く
struct LatestWeightText: View {
    let kg: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(WeightSummaryContent.kg(kg))
                .font(.system(size: 36, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .privacySensitive()
            Text("kg")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 「目標まで」「期限まで」の行（ホーム画面の小・中）
struct GoalSummaryRows: View {
    let content: WeightSummaryContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch content.goalLine {
            case .none:
                EmptyView()
            case .remaining(let kg):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("目標まで")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(WeightSummaryContent.kg(kg)) kg")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .privacySensitive()
                }
            case .achieved:
                Label("目標に届いています", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            case .maintenance:
                GoalLineText(goalLine: content.goalLine)
                    .font(.caption.weight(.semibold))
            }
            if let deadline = content.deadline {
                DeadlineText(status: deadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// 目標についての 1 行（ロック画面とキープモード用）
struct GoalLineText: View {
    let goalLine: WeightSummaryContent.GoalLine

    var body: some View {
        switch goalLine {
        case .none:
            EmptyView()
        case .remaining(let kg):
            Text("目標まで \(WeightSummaryContent.kg(kg)) kg")
                .monospacedDigit()
                .privacySensitive()
        case .achieved:
            Text("目標に届いています")
        case .maintenance(let lowerKg, let upperKg, let isInRange):
            VStack(alignment: .leading, spacing: 0) {
                Text("キープ中 \(WeightSummaryContent.kg(lowerKg))〜\(WeightSummaryContent.kg(upperKg)) kg")
                    .monospacedDigit()
                    .privacySensitive()
                Text(isInRange ? "範囲の中です" : "範囲から少し外れています")
                    .foregroundStyle(isInRange ? Color.green : Color.orange)
            }
        }
    }
}

/// 「期限まで ○ 日」
struct DeadlineText: View {
    let status: WidgetDeadlineStatus

    var body: some View {
        switch status {
        case .daysLeft(let days):
            Text("期限まで \(days) 日")
                .monospacedDigit()
        case .today:
            Text("今日が期限の日です")
        case .passed:
            Text("期限の日を過ぎました")
        }
    }
}

/// 記録がまだないとき
struct EmptyWeightView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "scalemass")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("体重を記録しましょう")
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - プレビュー

#Preview("小", as: .systemSmall) {
    WeightSummaryWidget()
} timeline: {
    WeightSummaryEntry(date: .now, snapshot: .sample)
    WeightSummaryEntry(date: .now, snapshot: .empty())
}

#Preview("中", as: .systemMedium) {
    WeightSummaryWidget()
} timeline: {
    WeightSummaryEntry(date: .now, snapshot: .sample)
}

#Preview("ロック画面：長方形", as: .accessoryRectangular) {
    WeightSummaryWidget()
} timeline: {
    WeightSummaryEntry(date: .now, snapshot: .sample)
}

#Preview("ロック画面：丸", as: .accessoryCircular) {
    WeightSummaryWidget()
} timeline: {
    WeightSummaryEntry(date: .now, snapshot: .sample)
}

#Preview("ロック画面：1 行", as: .accessoryInline) {
    WeightSummaryWidget()
} timeline: {
    WeightSummaryEntry(date: .now, snapshot: .sample)
}
