import SwiftUI
import Charts

/// 体重のグラフ（Swift Charts）。
///
/// - 点：実際に測った体重（1 日 1 点。同じ日に何回か測ったら平均）
/// - 実線：直近 3 週間の測った体重に引いた直線（線形回帰）。いまのペースを表す
/// - 点線：その直線をのばした予測（目標に届く日まで）
/// - 薄い帯（Pro）：早めの見込み〜遅めの見込みの幅。日々のブレが大きいほど広くなります
/// - 横線（緑）：目標体重
/// - 縦線：目標の期限。点線が縦線より左で横線に届けば「期限に間に合う」と、ひと目で分かります
///
/// 日々の上下（ブレ）は、なめらかにせず点のまま見せます。記録が少ないうちは直線の向きが変わりやすいので、
/// そのことはグラフの下の注意書きで伝えます。
///
/// Swift Charts では「マーク」（PointMark・LineMark・RuleMark）を並べるだけでグラフになります。
struct WeightChartView: View {
    /// 測った体重（1 日 1 件・古い順）
    let measured: [WeightPoint]
    /// 直近 3 週間の直線（実線）。記録が 3 日未満なら空
    let paceLine: [WeightPoint]
    /// 予測（点線）。目標がない・予測できないときは空
    let forecastLine: [WeightPoint]
    let goalWeightKg: Double?
    /// 目標の期限
    let deadline: Date?
    /// Pro：予測の幅（薄い帯）。Pro を使えないときは空
    var forecastBand: [ForecastBandPoint] = []
    /// Pro：リバウンド抑制モードのキープの範囲（薄い緑の帯）。モード中でなければ nil
    var keepRange: MaintenanceRange? = nil

    /// グラフに出す過去の日数（古すぎる記録まで出すと、最近の動きが見えにくくなるため）
    private let visibleHistoryDays = 90

    private var visibleMeasured: [WeightPoint] {
        guard let latest = measured.last?.date,
              let from = Calendar.current.date(byAdding: .day, value: -visibleHistoryDays, to: latest) else { return measured }
        return measured.filter { $0.date >= from }
    }

    /// 期限の縦線を出すかどうか。表示している期間より前に過ぎた期限は出さない（グラフが横に伸びすぎるため）。
    private var visibleDeadline: Date? {
        guard let deadline, let first = visibleMeasured.first?.date, deadline >= first else { return nil }
        return deadline
    }

    /// 縦軸の範囲。すべての点と目標体重が入るように、上下に少し余白をつける。
    private var yDomain: ClosedRange<Double> {
        var values = visibleMeasured.map(\.weightKg) + paceLine.map(\.weightKg) + forecastLine.map(\.weightKg)
            + forecastBand.flatMap { [$0.lowerKg, $0.upperKg] }
        if let goalWeightKg { values.append(goalWeightKg) }
        if let keepRange { values.append(contentsOf: [keepRange.lowerKg, keepRange.upperKg]) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max(0.5, (high - low) * 0.1)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                // 予測の幅（Pro）。いちばん先に描いて、ほかの線や点の後ろに置く
                ForEach(forecastBand, id: \.date) { point in
                    AreaMark(
                        x: .value("日付", point.date, unit: .day),
                        yStart: .value("早めの見込み", point.lowerKg),
                        yEnd: .value("遅めの見込み", point.upperKg)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                }

                // リバウンド抑制モードのキープの範囲。表示している期間の左端から右端まで、薄い緑の帯にする
                if let keepRange, let first = visibleMeasured.first?.date, let last = visibleMeasured.last?.date {
                    RectangleMark(
                        xStart: .value("日付", first, unit: .day),
                        xEnd: .value("日付", last, unit: .day),
                        yStart: .value("下の端", keepRange.lowerKg),
                        yEnd: .value("上の端", keepRange.upperKg)
                    )
                    .foregroundStyle(Color.green.opacity(0.15))
                }

                if let goalWeightKg {
                    RuleMark(y: .value("目標", goalWeightKg))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("目標 \(goalWeightKg, format: .number.precision(.fractionLength(1))) kg")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                }

                if let visibleDeadline {
                    RuleMark(x: .value("期限", visibleDeadline, unit: .day))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("期限 \(visibleDeadline, format: .dateTime.month().day())")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                }

                ForEach(visibleMeasured, id: \.date) { point in
                    PointMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("体重", point.weightKg)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .symbolSize(24)
                }

                // `series:` で線を分けないと、実線と点線が 1 本の線としてつながってしまう
                ForEach(paceLine, id: \.date) { point in
                    LineMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("体重", point.weightKg),
                        series: .value("線", "これまで")
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }

                ForEach(forecastLine, id: \.date) { point in
                    LineMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("体重", point.weightKg),
                        series: .value("線", "予測")
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 5]))
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 220)
            .accessibilityLabel("体重のグラフ")
            .accessibilityValue(accessibilitySummary)

            legend
        }
    }

    /// VoiceOver 用：グラフの中身をことばで伝える
    private var accessibilitySummary: Text {
        guard let last = visibleMeasured.last else { return Text("記録はまだありません") }
        let latestKg = last.weightKg.formatted(.number.precision(.fractionLength(1)))
        if let goalWeightKg {
            let goalKg = goalWeightKg.formatted(.number.precision(.fractionLength(1)))
            return Text("最新は \(latestKg) キログラム、目標は \(goalKg) キログラム")
        }
        return Text("最新は \(latestKg) キログラム")
    }

    /// 凡例（線や点の意味）。文字が大きいときは縦に並べる。
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
        legendItem("測った体重") {
            Circle().fill(Color.secondary.opacity(0.7)).frame(width: 7, height: 7)
        }
        if !paceLine.isEmpty {
            legendItem("直近 3 週間のペース") {
                Capsule().fill(Color.accentColor).frame(width: 16, height: 3)
            }
        }
        if !forecastLine.isEmpty {
            legendItem("予測") {
                DashLine().stroke(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 16, height: 3)
            }
        }
        if keepRange != nil {
            legendItem("キープの範囲") {
                RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.3))
                    .frame(width: 16, height: 9)
            }
        }
        if !forecastBand.isEmpty {
            legendItem("予測の幅") {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.25))
                    .frame(width: 16, height: 9)
            }
        }
    }

    private func legendItem(_ title: LocalizedStringKey, @ViewBuilder symbol: () -> some View) -> some View {
        HStack(spacing: 4) {
            symbol()
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 凡例の点線用：横 1 本の線
private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
