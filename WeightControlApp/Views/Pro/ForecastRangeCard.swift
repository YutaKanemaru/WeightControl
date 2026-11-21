import SwiftUI

/// ホームの「見込みの幅」カード（Pro 機能・フェーズ 12）。
///
/// 「達成の見込み」カードの 1 本の予測に加えて、「早ければ 3 月 8 日、遅くても 4 月 2 日ごろ」のような幅を出します。
/// 計算は `Logic/Pro/ForecastRangeEstimator`、グラフの薄い帯は `ForecastBandBuilder` です。
/// このカードは計算済みの結果を並べるだけです。
struct ForecastRangeCard: View {
    let range: ForecastRange

    /// 増減（+0.3 / -0.3）を表示する書式
    private static let signedKgFormat = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(1))
        .sign(strategy: .always(includingZero: false))

    var body: some View {
        DashboardCard(title: "見込みの幅", systemImage: "arrow.left.and.right", badge: "Pro") {
            MetricView(
                "早ければ〜遅くても",
                text: rangeText,
                unit: "ごろ",
                caption: Text("まん中の見込みは \(range.expectedDate, format: .dateTime.year().month().day())（上のカードと同じ日）"),
                size: .medium
            )

            MetricView(
                "ペースの幅（1 週間あたり）",
                text: Text("\(range.optimisticWeeklyChangeKg, format: Self.signedKgFormat)〜\(range.pessimisticWeeklyChangeKg, format: Self.signedKgFormat)"),
                unit: "kg",
                size: .medium
            )

            if let likelihood = range.deadlineLikelihood {
                likelihoodNotice(likelihood)
            }

            NoticeLabel("体重の日々のブレから、早め〜遅めの見込みを出しています。グラフの薄い帯がこの幅です。記録が直線に近いほど、幅はせまくなります。")
        }
    }

    /// 「3月8日〜4月2日」。遅めのペースだと届かないときは「3月8日〜まだ見えない」
    private var rangeText: Text {
        let earliest = Text(range.earliestDate, format: .dateTime.month().day())
        if let latest = range.latestReachDate {
            return Text("\(earliest)〜\(Text(latest, format: .dateTime.month().day()))")
        }
        return Text("\(earliest)〜まだ見えない")
    }

    @ViewBuilder
    private func likelihoodNotice(_ likelihood: ForecastRange.DeadlineLikelihood) -> some View {
        switch likelihood {
        case .likely:
            NoticeLabel("遅めの見込みでも、期限に間に合うペースです", style: .success)
        case .possible:
            NoticeLabel("早めのペースなら、期限に間に合う見込みです")
        case .unlikely:
            NoticeLabel("早めのペースでも、期限には少し届かない見込みです。期限をのばすのも、続けやすくする一つの方法です。")
        case .passed:
            // 期限を過ぎたことは「達成の見込み」カードで伝えるので、ここでは出さない
            EmptyView()
        }
    }
}

#Preview("見込みの幅") {
    let today = Calendar.current.startOfDay(for: .now)
    let range = ForecastRange(
        confidence: .reliable,
        recordedDays: 21,
        latestDate: today,
        earliestDate: Calendar.current.date(byAdding: .day, value: 50, to: today)!,
        expectedDate: Calendar.current.date(byAdding: .day, value: 62, to: today)!,
        latestReachDate: Calendar.current.date(byAdding: .day, value: 85, to: today)!,
        optimisticWeeklyChangeKg: -0.45,
        pessimisticWeeklyChangeKg: -0.25,
        deadlineLikelihood: .possible
    )
    ScrollView {
        VStack(spacing: 16) {
            ForecastRangeCard(range: range)
            ForecastRangeCard(range: range)
                .dynamicTypeSize(.accessibility2)
        }
        .padding()
    }
}
