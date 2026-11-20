import SwiftUI
import Charts

/// 体重のグラフ（Swift Charts）。
///
/// - 点：実際に測った体重（1 日 1 点。同じ日に何回か測ったら平均）
/// - 実線：ならした流れ（EMA でならした体重。コードでは「トレンド」。画面では「トレンド」という言葉を使わない）
/// - 点線：今のペースが続いた場合の予測（目標に届く日まで）
/// - 横線：目標体重
///
/// Swift Charts では「マーク」（PointMark・LineMark・RuleMark）を並べるだけでグラフになります。
struct WeightChartView: View {
    let trend: [TrendPoint]
    let forecastLine: [WeightPoint]
    let goalWeightKg: Double?

    /// グラフに出す過去の日数（古すぎる記録まで出すと、最近の動きが見えにくくなるため）
    private let visibleHistoryDays = 90

    private var visibleTrend: [TrendPoint] {
        guard let latest = trend.last?.date,
              let from = Calendar.current.date(byAdding: .day, value: -visibleHistoryDays, to: latest) else { return trend }
        return trend.filter { $0.date >= from }
    }

    /// 縦軸の範囲。すべての点と目標体重が入るように、上下に少し余白をつける。
    private var yDomain: ClosedRange<Double> {
        var values = visibleTrend.flatMap { [$0.measuredKg, $0.trendKg] } + forecastLine.map(\.weightKg)
        if let goalWeightKg { values.append(goalWeightKg) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max(0.5, (high - low) * 0.1)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                if let goalWeightKg {
                    RuleMark(y: .value("目標", goalWeightKg))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("目標 \(goalWeightKg, format: .number.precision(.fractionLength(1))) kg")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                }

                ForEach(visibleTrend, id: \.date) { point in
                    PointMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("体重", point.measuredKg)
                    )
                    .foregroundStyle(.gray.opacity(0.5))
                    .symbolSize(20)
                }

                // `series:` で線を分けないと、トレンドと予測が 1 本の線としてつながってしまう
                ForEach(visibleTrend, id: \.date) { point in
                    LineMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("体重", point.trendKg),
                        series: .value("線", "流れ")
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                }

                ForEach(forecastLine, id: \.date) { point in
                    LineMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("体重", point.weightKg),
                        series: .value("線", "予測")
                    )
                    .foregroundStyle(.blue.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
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

            legend
        }
    }

    /// 凡例（線や点の意味）
    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("測った体重") {
                Circle().fill(.gray.opacity(0.5)).frame(width: 7, height: 7)
            }
            legendItem("ならした流れ") {
                Capsule().fill(.blue).frame(width: 16, height: 3)
            }
            if !forecastLine.isEmpty {
                legendItem("予測") {
                    DashLine().stroke(.blue.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: 16, height: 3)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ title: LocalizedStringKey, @ViewBuilder symbol: () -> some View) -> some View {
        HStack(spacing: 4) {
            symbol()
            Text(title)
        }
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
