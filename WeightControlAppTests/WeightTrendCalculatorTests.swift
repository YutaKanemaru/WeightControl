import Foundation
import Testing
@testable import WeightControlApp

/// EMA トレンド（WeightTrendCalculator）と線形回帰（LinearRegression）のテスト
struct WeightTrendCalculatorTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int, hour: Int = 0) -> Date { TestCalendar.day(n, hour: hour) }

    @Test("記録がなければトレンドも空")
    func emptyInput() {
        #expect(WeightTrendCalculator.trend([], calendar: calendar).isEmpty)
    }

    @Test("最初のトレンドは最初の測定値そのもの")
    func firstPointEqualsMeasurement() {
        let trend = WeightTrendCalculator.trend([WeightPoint(date: day(0, hour: 7), weightKg: 70)], calendar: calendar)
        #expect(trend == [TrendPoint(date: day(0), measuredKg: 70, trendKg: 70)])
    }

    @Test("翌日のトレンドは、差の 1 割だけ動く")
    func movesByTenPercent() {
        let points = [
            WeightPoint(date: day(0), weightKg: 70),
            WeightPoint(date: day(1), weightKg: 71),
        ]
        let trend = WeightTrendCalculator.trend(points, calendar: calendar)
        #expect(trend.count == 2)
        #expect(isApproximately(trend[1].trendKg, 70.1))
        #expect(trend[1].measuredKg == 71)
    }

    @Test("記録が 3 日空いたら、3 日分まとめて追いつく（1 − 0.9³ = 27.1 %）")
    func catchesUpAfterGap() {
        let points = [
            WeightPoint(date: day(0), weightKg: 70),
            WeightPoint(date: day(3), weightKg: 71),
        ]
        let trend = WeightTrendCalculator.trend(points, calendar: calendar)
        #expect(isApproximately(trend[1].trendKg, 70.271))
    }

    @Test("同じ日の記録は平均して 1 件にまとめる")
    func averagesSameDay() {
        let points = [
            WeightPoint(date: day(0, hour: 7), weightKg: 70.0),
            WeightPoint(date: day(0, hour: 22), weightKg: 71.0),
        ]
        let trend = WeightTrendCalculator.trend(points, calendar: calendar)
        #expect(trend.count == 1)
        #expect(isApproximately(trend[0].measuredKg, 70.5))
        #expect(trend[0].date == day(0))
    }

    @Test("並び順がバラバラでも古い順に計算する")
    func sortsByDate() {
        let points = [
            WeightPoint(date: day(2), weightKg: 72),
            WeightPoint(date: day(0), weightKg: 70),
            WeightPoint(date: day(1), weightKg: 71),
        ]
        let trend = WeightTrendCalculator.trend(points, calendar: calendar)
        #expect(trend.map(\.date) == [day(0), day(1), day(2)])
        #expect(trend.map(\.measuredKg) == [70, 71, 72])
    }

    @Test("1 日おきに ±0.5 kg ぶれても、トレンドのぶれは小さい")
    func smoothsNoise() {
        let points = (0..<30).map { n in
            WeightPoint(date: day(n), weightKg: 70 + (n.isMultiple(of: 2) ? 0.5 : -0.5))
        }
        let trend = WeightTrendCalculator.trend(points, calendar: calendar)
        let lastWeek = trend.suffix(7).map(\.trendKg)
        let swing = (lastWeek.max() ?? 0) - (lastWeek.min() ?? 0)
        #expect(swing < 0.15) // 測定値のぶれは 1.0 kg
    }

    // MARK: - 線形回帰

    @Test("一直線上の点なら、傾きと切片がぴったり求まる")
    func fitsExactLine() throws {
        let samples = (0..<5).map { (x: Double($0), y: 2 * Double($0) + 1) }
        let fit = try #require(LinearRegression.fit(samples))
        #expect(isApproximately(fit.slope, 2))
        #expect(isApproximately(fit.intercept, 1))
        #expect(isApproximately(fit.value(at: 10), 21))
    }

    @Test("ばらついた点には、ずれが最小になる直線を引く")
    func fitsNoisyPoints() throws {
        // (0,1) (1,3) (2,2) (3,4) → 傾き 0.8、切片 1.3
        let samples: [(x: Double, y: Double)] = [(0, 1), (1, 3), (2, 2), (3, 4)]
        let fit = try #require(LinearRegression.fit(samples))
        #expect(isApproximately(fit.slope, 0.8))
        #expect(isApproximately(fit.intercept, 1.3))
    }

    @Test("点が 2 つ未満、または x がすべて同じなら直線は引けない")
    func cannotFitDegenerateInput() {
        #expect(LinearRegression.fit([]) == nil)
        #expect(LinearRegression.fit([(x: 0, y: 1)]) == nil)
        #expect(LinearRegression.fit([(x: 1, y: 1), (x: 1, y: 2)]) == nil)
    }
}
