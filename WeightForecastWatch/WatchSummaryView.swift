import SwiftUI

/// Watch アプリの最初の画面：最新の体重・目標まで・期限まで・連続記録と「記録する」ボタン。仕様は docs/WATCH.md。
///
/// 大事な数字は大きく太く（`monospacedDigit()` で桁がずれない）、説明は小さく控えめにしています。
struct WatchSummaryView: View {
    @Environment(PhoneConnection.self) private var connection
    @State private var isRecording = false

    var body: some View {
        let summary = connection.summary()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    LatestWeightSection(summary: summary)
                    GoalSection(summary: summary)
                    if summary.streakDays >= 1 || summary.hasRecordedToday {
                        StreakRow(summary: summary)
                    }
                    Button {
                        isRecording = true
                    } label: {
                        Label("記録する", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("体重予報")
            .navigationDestination(isPresented: $isRecording) {
                RecordWeightView(
                    startKg: WatchDisplay.startWeightKg(snapshot: connection.snapshot, pending: connection.pending),
                    previousKg: summary.latest?.weightKg
                )
            }
        }
    }
}

/// 最新の体重（いちばん大きな数字）
private struct LatestWeightSection: View {
    let summary: WatchSummary

    var body: some View {
        if let latest = summary.latest {
            VStack(alignment: .leading, spacing: 0) {
                Label("体重", systemImage: "scalemass.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(WatchSummary.kg(latest.weightKg))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .privacySensitive()
                    Text("kg")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if latest.isPending {
                    Label("iPhone に送信待ち", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else if summary.isWaitingForPhone {
            NoticeText("iPhone のアプリを開くと、ここに体重と目標が出ます。", systemImage: "iphone")
        } else {
            NoticeText("まだ記録がありません。下のボタンから記録できます。", systemImage: "scalemass")
        }
    }
}

/// 目標まで・期限まで
private struct GoalSection: View {
    let summary: WatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch summary.goal {
            case .remaining(let kg, _):
                MetricRow(title: "目標まで", value: WatchSummary.kg(kg), unit: "kg", systemImage: "flag.fill")
            case .achieved:
                Label("目標達成", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            case .maintenance(let lowerKg, let upperKg, let isInRange):
                VStack(alignment: .leading, spacing: 0) {
                    Text("キープ中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(WatchSummary.kg(lowerKg))〜\(WatchSummary.kg(upperKg)) kg")
                        .font(.headline)
                        .monospacedDigit()
                        .privacySensitive()
                    Label(isInRange ? "範囲の中です" : "範囲から少し外れています",
                          systemImage: isInRange ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(isInRange ? .green : .orange)
                }
            case .noRecord, .noGoal:
                EmptyView()
            }
            if let deadline = summary.deadline {
                DeadlineRow(status: deadline)
            }
        }
    }
}

/// 「目標まで 3.2 kg」のような 1 行（数字を大きく）
private struct MetricRow: View {
    let title: LocalizedStringKey
    let value: String
    let unit: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .privacySensitive()
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 期限まで
private struct DeadlineRow: View {
    let status: WidgetDeadlineStatus

    var body: some View {
        switch status {
        case .daysLeft(let days):
            MetricRow(title: "期限まで", value: "\(days)", unit: "日", systemImage: "calendar")
        case .today:
            Label("今日が期限です", systemImage: "calendar")
                .font(.caption)
        case .passed:
            Label("期限を過ぎました。iPhone で見直せます", systemImage: "calendar")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 連続記録と、今日の記録
private struct StreakRow: View {
    let summary: WatchSummary

    var body: some View {
        HStack(spacing: 6) {
            if summary.hasRecordedToday {
                Label("今日は記録ずみ", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if summary.streakDays >= 2 {
                Text("\(summary.streakDays) 日連続")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// 補足の一文（アイコンつき、小さく控えめ）
private struct NoticeText: View {
    let text: LocalizedStringKey
    let systemImage: String

    init(_ text: LocalizedStringKey, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    WatchSummaryView()
        .environment(PhoneConnection())
}
