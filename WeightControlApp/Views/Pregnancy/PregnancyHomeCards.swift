import SwiftUI
import SwiftData
import Charts

// 妊娠中モードのホームに並べるカード（docs/PREGNANCY_MODE.md の「ホームに出すもの」）。
// どのカードも、計算済みの結果（`PregnancyDashboard`）を受け取って表示するだけです。
// 「ダイエット」「減らしましょう」「食べすぎ」「太る」などの言葉は使いません。

/// kg を小数 1 桁で表示する書式
private let kgFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
/// 増減（+4.2 / -0.3）を表示する書式
private let signedKgFormat = FloatingPointFormatStyle<Double>.number
    .precision(.fractionLength(1))
    .sign(strategy: .always(includingZero: true))

// MARK: - いちばん上：週数と増え方

struct PregnancySummaryCard: View {
    let dashboard: PregnancyDashboard
    let latestDate: Date?

    var body: some View {
        DashboardCard(title: "妊娠中モード", systemImage: "figure.and.child.holdinghands") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline) {
                    weeks
                    Spacer(minLength: 16)
                    gain
                }
                VStack(alignment: .leading, spacing: 12) {
                    weeks
                    gain
                }
            }
            if let band = dashboard.bandToday {
                Text("今週の目安の帯：\(band.lowerGainKg, format: signedKgFormat)〜\(band.upperGainKg, format: signedKgFormat) kg（\(targetLabel)）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var weeks: some View {
        MetricView(
            "妊娠",
            text: gestationalAgeText(dashboard.age),
            caption: latestDate.map { Text("最新の記録 \($0, format: .dateTime.month().day())") },
            size: .large
        )
    }

    @ViewBuilder
    private var gain: some View {
        if let gainKg = dashboard.latestGainKg {
            MetricView(
                "妊娠前から",
                text: Text(gainKg, format: signedKgFormat),
                unit: "kg",
                caption: dashboard.latestWeightKg.map { Text("\($0, format: kgFormat) kg") },
                size: .medium
            )
        }
    }

    private var targetLabel: String {
        switch dashboard.target {
        case .custom: String(localized: "健診で言われた目安")
        case .general, .needsDoctor: String(localized: "一般的な目安")
        }
    }
}

// MARK: - ほめる言葉

/// 体重の増減ではなく、記録を続けていることをほめるカード
struct PregnancyPraiseCard: View {
    let streakDays: Int
    let recentRecordedDays: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if streakDays > 0 {
                    Text("連続 \(streakDays) 日記録中")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private var message: LocalizedStringKey {
        if recentRecordedDays >= 7 {
            "記録を続けられていて、すてきです。体を大事にしている毎日の積み重ねです。"
        } else if recentRecordedDays > 0 {
            "記録できました。無理せず、測れた日だけで大丈夫です。"
        } else {
            "体調のよいときに、体重を測ってみましょう。週に 1〜2 回でも、増え方が分かります。"
        }
    }
}

// MARK: - グラフ

/// 測った体重と、増え方の目安の帯のグラフ。目標の横線・予測の点線・期限の縦線は描かず、出産予定日の縦線だけ描く。
struct PregnancyChartCard: View {
    let dashboard: PregnancyDashboard
    /// 妊娠が始まってからの測った体重（1 日 1 件・古い順）
    let measured: [WeightPoint]
    let dueDate: Date

    var body: some View {
        DashboardCard(title: "体重のグラフ", systemImage: "chart.xyaxis.line") {
            Chart {
                ForEach(dashboard.bandPoints, id: \.date) { point in
                    AreaMark(
                        x: .value("日付", point.date, unit: .day),
                        yStart: .value("目安の下の端", point.lowerKg),
                        yEnd: .value("目安の上の端", point.upperKg)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                }

                RuleMark(x: .value("出産予定日", dueDate, unit: .day))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("予定日 \(dueDate, format: .dateTime.month().day())")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                ForEach(measured, id: \.date) { point in
                    PointMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("体重", point.weightKg)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(24)
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: weekTickDates) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text("\(GestationalAgeCalculator.age(dueDate: dueDate, on: date).weeks) 週")
                        }
                    }
                }
            }
            .frame(height: 220)
            .accessibilityLabel("体重のグラフ")
            .accessibilityValue(accessibilitySummary)

            legend

            if dashboard.bandPoints.isEmpty {
                NoticeLabel("健診で言われた目安を設定に入れると、グラフに目安の帯を描きます。")
            }
        }
    }

    private var start: Date {
        GestationalAgeCalculator.startDate(dueDate: dueDate)
    }

    /// 横軸：妊娠 0 週から、出産予定日（記録が予定日より後まであればそこ）まで
    private var xDomain: ClosedRange<Date> {
        let end = max(dueDate, measured.last?.date ?? dueDate)
        return start...end
    }

    /// 縦軸の範囲。帯と点がすべて入るように、上下に少し余白をつける
    private var yDomain: ClosedRange<Double> {
        let values = measured.map(\.weightKg) + dashboard.bandPoints.flatMap { [$0.lowerKg, $0.upperKg] }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max(0.5, (high - low) * 0.1)
        return (low - padding)...(high + padding)
    }

    /// 横軸の目盛り：0・8・16・24・32・40 週
    private var weekTickDates: [Date] {
        stride(from: 0, through: 40, by: 8).map { week in
            DayMath.date(byAddingDays: week * 7, to: start, calendar: .current)
        }
    }

    private var accessibilitySummary: Text {
        guard let gainKg = dashboard.latestGainKg else { return Text("記録はまだありません") }
        let gain = gainKg.formatted(signedKgFormat)
        return Text("妊娠前から \(gain) キログラム")
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var legendItems: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
            Text("測った体重")
        }
        .accessibilityElement(children: .combine)
        if !dashboard.bandPoints.isEmpty {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.25))
                    .frame(width: 16, height: 9)
                Text("増え方の目安")
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - ひとこと

/// 目安の帯に対してどこにいるかを、責めずに伝えるカード。色で良し悪しを表さない（外れても赤にしない）。
struct PregnancyStatusCard: View {
    let dashboard: PregnancyDashboard

    var body: some View {
        DashboardCard(title: "増え方の目安", systemImage: "arrow.up.right") {
            Text(statusMessage)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if dashboard.showsRapidGainNote {
                NoticeLabel("ここ数週間、体重が早めに増えています。急に増えたときは、健診を待たずに相談すると安心です。")
            }
            if dashboard.hasFewRecentRecords, dashboard.status != .noRecords {
                NoticeLabel("測れた日だけで大丈夫です。週に 1〜2 回でも、増え方が分かります。")
            }
        }
    }

    private var statusMessage: LocalizedStringKey {
        switch dashboard.status {
        case .noRecords:
            "体重を記録すると、目安の帯と並べて見られます。"
        case .noGuide(.multiple):
            "双子などのときは、増え方の目安が人によって大きくちがうため、アプリからは一般的な目安を出していません。健診で言われた目安を設定に入れると、その目安で見られます。"
        case .noGuide(.veryHighBMI):
            "妊娠前の BMI が 30 以上のときは、増え方の目安は一人ひとりに合わせて決めることになっています（上限 5 kg までが目安とされています）。健診で言われた目安を設定に入れると、その目安で見られます。"
        case .withinRange:
            "目安の範囲で増えています。記録を続けられていて、すてきです。"
        case .belowRange:
            "目安より少なめです。食事や体調で気になることがあれば、次の健診で相談してみましょう。"
        case .aboveRange:
            "目安より多めです。気になる変化があれば、次の健診で相談してみましょう。"
        }
    }
}

// MARK: - 食事

/// 時期に合わせた食事の一文。摂取カロリーの「目安の数字」は出さない（必要な量は人によって大きくちがうため）。
struct PregnancyNutritionCard: View {
    let trimester: PregnancyTrimester

    var body: some View {
        DashboardCard(title: "食事", systemImage: "fork.knife") {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("出典：日本人の食事摂取基準（2025 年版）。健診で言われたことを優先してください。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var message: LocalizedStringKey {
        switch trimester {
        case .early:
            "この時期は、ふだんの食事にほんの少し（+50 kcal くらい）が目安とされています。つわりのときは、食べられるものを食べられるときに。"
        case .middle:
            "ふだんより +250 kcal くらいが目安とされています（おにぎり 1 個〈180 kcal〉より少し多いくらい）。"
        case .late:
            "ふだんより +450 kcal くらいが目安とされています。"
        }
    }
}

// MARK: - 出産予定日から 2 週間たったとき

/// 「出産予定日をすぎました。妊娠中モードを続けますか？」。お祝いの言葉は入れない（つらい理由で終える人もいるため）。
struct PregnancyCheckInCard: View {
    let plan: PregnancyPlan
    let onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        DashboardCard(title: "出産予定日をすぎました", systemImage: "calendar") {
            Text("妊娠中モードを続けますか？ 終えても、記録はそのまま残ります。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack { buttons }
                VStack { buttons }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            onContinue()
        } label: {
            Text("続ける")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        Button {
            plan.endedAt = .now
            try? modelContext.save()
        } label: {
            Text("終える")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - 終えたあと

/// 妊娠中モードを終えたあと、前の目標を一時停止しているときのカード。すぐに減量の目標を自動で再開しない。
struct PregnancyEndedGoalCard: View {
    let goal: WeightGoal
    let currentWeightKg: Double?
    let onResume: () -> Void

    var body: some View {
        DashboardCard(title: "目標を立て直しましょう", systemImage: "flag") {
            Text("産後の体は回復の途中です。授乳中は、ふだんより +350 kcal ほどが目安とされています（日本人の食事摂取基準 2025 年版）。減量を始める時期は、産後の健診などで相談してください。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                EditGoalView(goal: goal, currentWeightKg: currentWeightKg)
            } label: {
                Label("目標を立て直す", systemImage: "flag")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button {
                onResume()
            } label: {
                Text("前の目標に戻す")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("それまでは、予測やカロリーの目安は出さずに、記録とグラフだけを表示します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
