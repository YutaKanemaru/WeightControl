import Foundation
import Testing
@testable import WeightControlApp

/// 幅付きの予測が出なかったときにテストを止めるためのエラー
private struct RangeNotAvailable: Error {}

/// 幅付きの予測（ForecastRangeEstimator）と、傾きの標準誤差（LinearRegression）のテスト
struct ForecastRangeEstimatorTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    /// 80 kg から毎日 0.1 kg ずつ減る記録を `days` 日分（直線にぴったり乗る）
    private func steadyLoss(days: Int) -> [WeightPoint] {
        (0..<days).map { WeightPoint(date: day($0), weightKg: 80 - 0.1 * Double($0)) }
    }

    /// 毎日 0.02 kg ずつ減りながら、1 日おきに +0.5 / −0.5 kg ぶれる記録 21 日分
    private func noisySlowLoss() -> [WeightPoint] {
        (0..<21).map { n in
            WeightPoint(date: day(n), weightKg: 80 - 0.02 * Double(n) + (n.isMultiple(of: 2) ? 0.5 : -0.5))
        }
    }

    private func estimate(
        _ points: [WeightPoint],
        goal: Double,
        deadline: Date? = nil
    ) -> ForecastRangeResult {
        ForecastRangeEstimator.estimate(
            points: points,
            goalWeightKg: goal,
            deadline: deadline,
            now: points.map(\.date).max() ?? day(0),
            calendar: calendar
        )
    }

    private func available(_ result: ForecastRangeResult) throws -> ForecastRange {
        guard case .available(let range) = result else {
            Issue.record("幅付きの予測が出ていない: \(result)")
            throw RangeNotAvailable()
        }
        return range
    }

    /// 無料版の予測で届く日
    private func centralDate(_ points: [WeightPoint], goal: Double) -> Date? {
        let result = GoalForecaster.forecast(
            points: points, goalWeightKg: goal, deadline: nil,
            now: points.map(\.date).max() ?? day(0), calendar: calendar
        )
        guard case .available(let forecast) = result, case .willReach(let date) = forecast.outcome else { return nil }
        return date
    }

    // MARK: - 傾きの標準誤差

    @Test("直線にぴったり乗る点なら、傾きの標準誤差はほぼ 0")
    func standardErrorOfPerfectLine() {
        #expect(ForecastRangeEstimator.slopeStandardError(points: steadyLoss(days: 21), calendar: calendar) < 1e-9)
    }

    @Test("1 日おきに ±0.5 kg ぶれる記録なら、傾きの標準誤差は約 0.0189 kg/日")
    func standardErrorOfNoisyData() {
        let error = ForecastRangeEstimator.slopeStandardError(points: noisySlowLoss(), calendar: calendar)
        #expect(isApproximately(error, 0.018922, tolerance: 1e-5))
    }

    @Test("点が 3 つ未満なら標準誤差は出せない")
    func standardErrorNeedsThreePoints() {
        let samples: [(x: Double, y: Double)] = [(x: 0, y: 70), (x: 1, y: 71)]
        let fit = LinearFit(slope: 1, intercept: 70)
        #expect(LinearRegression.slopeStandardError(samples, fit: fit) == nil)
    }

    // MARK: - 予測できないとき

    @Test("記録が 2 日だけなら、まだ予測できない（無料版と同じ）")
    func insufficientData() {
        #expect(estimate(steadyLoss(days: 2), goal: 70) == .insufficientData(recordedDays: 2, requiredDays: GoalForecaster.minimumRecordedDays))
    }

    @Test("もう目標に届いていれば reached")
    func reached() {
        let points = (0..<14).map { WeightPoint(date: day($0), weightKg: 70) }
        #expect(estimate(points, goal: 70) == .reached)
    }

    @Test("目標と逆向きに動いていれば、早めの見込みで届きそうでも notApproaching（無料版にそろえる）")
    func notApproaching() {
        let points = (0..<14).map { WeightPoint(date: day($0), weightKg: 70 + 0.05 * Double($0)) }
        #expect(estimate(points, goal: 65) == .notApproaching)
    }

    // MARK: - 幅

    @Test("直線にぴったり乗る記録でも、傾きの 1 割の幅を持たせる（93 日目〜109 日目、まん中は 100 日目）")
    func minimumSpreadForPerfectLine() throws {
        // 20 日目に 78.0 kg、毎日 0.1 kg 減。目標 70 kg まで 8 kg
        // まん中:   8 ÷ 0.10 = 80 日後   → 100 日目
        // 早め:     8 ÷ 0.11 ≈ 72.7 日後 → 73 日後 → 93 日目
        // 遅め:     8 ÷ 0.09 ≈ 88.9 日後 → 89 日後 → 109 日目
        let range = try available(estimate(steadyLoss(days: 21), goal: 70))
        #expect(range.expectedDate == day(100))
        #expect(range.earliestDate == day(93))
        #expect(range.latestReachDate == day(109))
        #expect(isApproximately(range.optimisticWeeklyChangeKg, -0.77, tolerance: 1e-6))
        #expect(isApproximately(range.pessimisticWeeklyChangeKg, -0.63, tolerance: 1e-6))
        #expect(range.confidence == .reliable)
        #expect(range.recordedDays == 21)
        #expect(range.latestDate == day(20))
    }

    @Test("まん中の日は無料版の予測（GoalForecaster）と同じ日")
    func expectedDateMatchesFreeForecast() throws {
        let points = noisySlowLoss()
        let range = try available(estimate(points, goal: 79))
        #expect(range.expectedDate == centralDate(points, goal: 79))
    }

    @Test("ブレが大きく、遅めのペースだと横ばいになるなら、遅めの日は nil（まだ見えない）")
    func pessimisticCanBeOpenEnded() throws {
        // 傾き −0.02、標準誤差 約 0.0189 → 遅めのペースは 約 −0.001 kg/日（週 0.01 kg 未満で横ばい）
        // 今の体重の目安 約 79.624 kg、目標 79 kg まで 約 0.624 kg
        // まん中: 0.624 ÷ 0.02 ≈ 31.2 → 32 日後 → 52 日目
        // 早め:   0.624 ÷ 0.0389 ≈ 16.03 → 17 日後 → 37 日目
        let range = try available(estimate(noisySlowLoss(), goal: 79))
        #expect(range.expectedDate == day(52))
        #expect(range.earliestDate == day(37))
        #expect(range.latestReachDate == nil)
    }

    @Test("ブレが大きいほど幅が広い")
    func noisierDataGivesWiderRange() throws {
        let clean = (0..<21).map { WeightPoint(date: day($0), weightKg: 80 - 0.1 * Double($0)) }
        let noisy = (0..<21).map { n in
            WeightPoint(date: day(n), weightKg: 80 - 0.1 * Double(n) + (n.isMultiple(of: 2) ? 0.5 : -0.5))
        }
        let cleanRange = try available(estimate(clean, goal: 70))
        let noisyRange = try available(estimate(noisy, goal: 70))
        let cleanLatest = try #require(cleanRange.latestReachDate)
        let noisyLatest = try #require(noisyRange.latestReachDate)
        let cleanSpan = DayMath.days(from: cleanRange.earliestDate, to: cleanLatest, calendar: calendar)
        let noisySpan = DayMath.days(from: noisyRange.earliestDate, to: noisyLatest, calendar: calendar)
        // ぴったりの記録は 16 日、ぶれる記録は 31 日の幅になる
        #expect(noisySpan > cleanSpan)
        #expect(noisyRange.earliestDate <= noisyRange.expectedDate)
        #expect(noisyRange.expectedDate <= noisyLatest)
    }

    @Test("増量の目標でも、早め〜遅めの順に並ぶ（48 日目〜54 日目、まん中は 50 日目）")
    func gainGoal() throws {
        // 20 日目に 62.0 kg、毎日 0.1 kg 増。目標 65 kg まで 3 kg
        // まん中: 3 ÷ 0.10 = 30 日後 → 50 日目
        // 早め:   3 ÷ 0.11 ≈ 27.3 → 28 日後 → 48 日目
        // 遅め:   3 ÷ 0.09 ≈ 33.3 → 34 日後 → 54 日目
        let points = (0..<21).map { WeightPoint(date: day($0), weightKg: 60 + 0.1 * Double($0)) }
        let range = try available(estimate(points, goal: 65))
        #expect(range.expectedDate == day(50))
        #expect(range.earliestDate == day(48))
        #expect(range.latestReachDate == day(54))
    }

    // MARK: - 期限

    @Test("期限の見込み：遅めでも間に合う / 早めなら間に合う / 早めでも間に合わない / 過ぎている")
    func deadlineLikelihood() throws {
        // 幅は 93 日目〜109 日目、今日は 20 日目
        let points = steadyLoss(days: 21)
        #expect(try available(estimate(points, goal: 70, deadline: day(120))).deadlineLikelihood == .likely)
        #expect(try available(estimate(points, goal: 70, deadline: day(109))).deadlineLikelihood == .likely)
        #expect(try available(estimate(points, goal: 70, deadline: day(95))).deadlineLikelihood == .possible)
        #expect(try available(estimate(points, goal: 70, deadline: day(93))).deadlineLikelihood == .possible)
        #expect(try available(estimate(points, goal: 70, deadline: day(90))).deadlineLikelihood == .unlikely)
        #expect(try available(estimate(points, goal: 70, deadline: day(10))).deadlineLikelihood == .passed)
        #expect(try available(estimate(points, goal: 70)).deadlineLikelihood == nil)
    }

    @Test("遅めの日が見えないときは、期限が遠くても likely にはしない")
    func openEndedRangeIsNeverLikely() throws {
        let range = try available(estimate(noisySlowLoss(), goal: 79, deadline: day(700)))
        #expect(range.deadlineLikelihood == .possible)
    }
}
