import SwiftUI
import WidgetKit

// 文字盤のコンプリケーション 4 種類（docs/WATCH.md の「コンプリケーションの種類」）。
// 置き場所（family）は、隅＝accessoryCorner、丸＝accessoryCircular、1 行＝accessoryInline、長方形＝accessoryRectangular。
// 色は文字盤が決めるので、強調したいところだけ `widgetAccentable()` を付けています。数字は `privacySensitive()` で、ロック中は隠れます。

// MARK: - 目標まで

struct GoalRemainingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchGoalRemaining", provider: WatchComplicationProvider()) { entry in
            GoalRemainingView(summary: entry.summary)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("目標まで")
        .description("目標まであと何 kg かと、進み具合を表示します。")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryInline])
    }
}

struct GoalRemainingView: View {
    let summary: WatchSummary
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCorner:
            corner
        case .accessoryInline:
            inline
        default:
            circular
        }
    }

    @ViewBuilder private var corner: some View {
        switch summary.goal {
        case .remaining(let kg, let progress):
            Text(WatchSummary.kg(kg))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .privacySensitive()
                .widgetCurvesContent()
                .widgetLabel {
                    if let progress {
                        Gauge(value: clamped(progress)) {
                            Text("目標まで")
                        }
                        .tint(.accentColor)
                    } else {
                        Text("目標まで")
                    }
                }
        case .achieved:
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel { Text("目標達成") }
        case .maintenance(_, _, let isInRange):
            Image(systemName: isInRange ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel { Text(isInRange ? "キープ中" : "キープの範囲外") }
        case .noRecord, .noGoal:
            Image(systemName: "flag")
                .font(.title3)
                .widgetLabel { Text("目標まで") }
        }
    }

    @ViewBuilder private var circular: some View {
        switch summary.goal {
        case .remaining(let kg, let progress):
            Gauge(value: clamped(progress ?? 0)) {
                Image(systemName: "flag.fill")
            } currentValueLabel: {
                Text(WatchSummary.kg(kg))
                    .monospacedDigit()
                    .privacySensitive()
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
            .accessibilityLabel("目標まで \(WatchSummary.kg(kg)) kg")
        case .achieved:
            IconCircle(systemImage: "checkmark.seal.fill", text: "達成")
        case .maintenance(_, _, let isInRange):
            IconCircle(systemImage: isInRange ? "checkmark.circle.fill" : "exclamationmark.circle", text: "キープ")
        case .noRecord, .noGoal:
            IconCircle(systemImage: "flag", text: "目標")
        }
    }

    @ViewBuilder private var inline: some View {
        switch summary.goal {
        case .remaining(let kg, _):
            Text("目標まで \(WatchSummary.kg(kg)) kg")
                .privacySensitive()
        case .achieved:
            Label("目標達成", systemImage: "checkmark.seal.fill")
        case .maintenance(_, _, let isInRange):
            Label(isInRange ? "キープ中" : "キープの範囲外", systemImage: "scalemass.fill")
        case .noRecord, .noGoal:
            Label("体重を記録しましょう", systemImage: "scalemass")
        }
    }
}

// MARK: - 期限まで

struct DeadlineComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchDeadline", provider: WatchComplicationProvider()) { entry in
            DeadlineView(summary: entry.summary)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("期限まで")
        .description("目標の期限まであと何日かを表示します。")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryInline])
    }
}

struct DeadlineView: View {
    let summary: WatchSummary
    @Environment(\.widgetFamily) private var family

    /// 大きく出す文字（「45」「今日」など）と、添える文字
    private var texts: (main: String, label: String) {
        switch summary.deadline {
        case .daysLeft(let days):
            return ("\(days)", String(localized: "期限まで \(days) 日"))
        case .today:
            return (String(localized: "今日"), String(localized: "今日が期限"))
        case .passed:
            return (String(localized: "すぎ"), String(localized: "期限すぎ"))
        case nil:
            break
        }
        switch summary.goal {
        case .achieved:
            return (String(localized: "達成"), String(localized: "目標達成"))
        case .maintenance:
            return (String(localized: "キープ"), String(localized: "キープ中"))
        case .remaining, .noRecord, .noGoal:
            return ("--", String(localized: "期限まで"))
        }
    }

    var body: some View {
        let texts = texts
        switch family {
        case .accessoryCorner:
            Text(texts.main)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel { Text(texts.label) }
        case .accessoryInline:
            Label(texts.label, systemImage: "calendar")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(texts.main)
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .widgetAccentable()
                    if case .daysLeft = summary.deadline {
                        Text("日")
                            .font(.caption2)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(texts.label)
        }
    }
}

// MARK: - 連続記録

struct StreakComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchStreak", provider: WatchComplicationProvider()) { entry in
            StreakView(summary: entry.summary)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("連続記録")
        .description("体重を続けて記録している日数を表示します。")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryInline])
    }
}

struct StreakView: View {
    let summary: WatchSummary
    @Environment(\.widgetFamily) private var family

    private var icon: String {
        summary.hasRecordedToday ? "checkmark.circle.fill" : "circle"
    }

    var body: some View {
        let days = summary.streakDays
        switch family {
        case .accessoryCorner:
            Text("\(days)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel { Text("連続 \(days) 日") }
        case .accessoryInline:
            Label("連続 \(days) 日", systemImage: icon)
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.caption2)
                    Text("\(days)")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .widgetAccentable()
                    Text("日")
                        .font(.caption2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("連続 \(days) 日")
        }
    }
}

// MARK: - まとめ（長方形）

struct SummaryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchSummary", provider: WatchComplicationProvider()) { entry in
            SummaryRectangularView(summary: entry.summary)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("体重と目標")
        .description("体重・目標まで・期限まで・連続記録をまとめて表示します。")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct SummaryRectangularView: View {
    let summary: WatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let latest = summary.latest {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Image(systemName: "scalemass.fill")
                        .font(.caption)
                    Text(WatchSummary.kg(latest.weightKg))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .privacySensitive()
                        .widgetAccentable()
                    Text("kg")
                        .font(.caption)
                    Spacer(minLength: 4)
                    if summary.streakDays >= 1 {
                        Text("連続\(summary.streakDays)日")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
                goalLine
                    .font(.caption)
                    .privacySensitive()
                deadlineLine
                    .font(.caption)
            } else {
                Label("体重を記録しましょう", systemImage: "scalemass")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var goalLine: some View {
        switch summary.goal {
        case .remaining(let kg, _):
            Text("目標まで \(WatchSummary.kg(kg)) kg")
        case .achieved:
            Text("目標達成")
        case .maintenance(let lowerKg, let upperKg, _):
            Text("キープ \(WatchSummary.kg(lowerKg))〜\(WatchSummary.kg(upperKg)) kg")
        case .noRecord, .noGoal:
            EmptyView()
        }
    }

    @ViewBuilder private var deadlineLine: some View {
        switch summary.deadline {
        case .daysLeft(let days): Text("期限まで \(days) 日")
        case .today: Text("今日が期限")
        case .passed: Text("期限すぎ")
        case nil: EmptyView()
        }
    }
}

// MARK: - 共通の部品

/// 丸の置き場所に、アイコンと短い文字を出す
private struct IconCircle: View {
    let systemImage: String
    let text: LocalizedStringKey

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .widgetAccentable()
                Text(text)
                    .font(.caption2)
            }
        }
    }
}

private func clamped(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
