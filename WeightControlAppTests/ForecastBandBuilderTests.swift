import Foundation
import Testing
@testable import WeightControlApp

/// グラフの「予測の幅」の帯（ForecastBandBuilder）のテスト
struct ForecastBandBuilderTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    /// 0 日目から、早めは `optimisticDays` 日後・まん中は `expectedDays` 日後・遅めは `latestDays` 日後に届く幅
    private func range(
        optimisticWeeklyKg: Double,
        pessimisticWeeklyKg: Double,
        earliestDays: Int,
        expectedDays: Int,
        latestDays: Int?
    ) -> ForecastRange {
        ForecastRange(
            confidence: .reliable,
            recordedDays: 21,
            latestDate: day(0),
            earliestDate: day(earliestDays),
            expectedDate: day(expectedDays),
            latestReachDate: latestDays.map { day($0) },
            optimisticWeeklyChangeKg: optimisticWeeklyKg,
            pessimisticWeeklyChangeKg: pessimisticWeeklyKg,
            deadlineLikelihood: nil
        )
    }

    @Test("早めの直線と遅めの直線の間を帯にし、目標を越えたら目標に止める（減量）")
    func losingBand() {
        // 70 kg → 69 kg。早めは 1 日 0.125 kg（8 日で届く）、遅めは 1 日 1/14 kg（14 日で届く）
        let band = ForecastBandBuilder.band(
            for: range(optimisticWeeklyKg: -0.875, pessimisticWeeklyKg: -0.5, earliestDays: 8, expectedDays: 10, latestDays: 14),
            startKg: 70,
            goalWeightKg: 69,
            calendar: calendar
        )
        // 点は 0・7 日目（7 日ごと）、8 日目（早めが届いて折れる日）、14 日目（遅めが届く日＝終わり）
        #expect(band.map(\.date) == [day(0), day(7), day(8), day(14)])
        #expect(band[0].lowerKg == 70 && band[0].upperKg == 70)
        #expect(isApproximately(band[1].lowerKg, 69.125))
        #expect(isApproximately(band[1].upperKg, 69.5))
        #expect(isApproximately(band[2].lowerKg, 69))
        #expect(isApproximately(band[2].upperKg, 70 - 8.0 / 14))
        #expect(isApproximately(band[3].lowerKg, 69))
        #expect(isApproximately(band[3].upperKg, 69))
    }

    @Test("遅めだと届かないときは、まん中の見込みまでの日数の 2 倍で切る")
    func cappedWhenPessimisticNeverReaches() {
        // 遅めのペースは逆向き（少し増える）。帯は 10 × 2 = 20 日目まで
        let band = ForecastBandBuilder.band(
            for: range(optimisticWeeklyKg: -0.875, pessimisticWeeklyKg: 0.1, earliestDays: 8, expectedDays: 10, latestDays: nil),
            startKg: 70,
            goalWeightKg: 69,
            calendar: calendar
        )
        #expect(band.last?.date == day(20))
        #expect(isApproximately(band.last?.lowerKg ?? 0, 69))
        // 逆向きの線は目標で止めない（目標から離れる向きなので）
        #expect(isApproximately(band.last?.upperKg ?? 0, 70 + 0.1 / 7 * 20))
    }

    @Test("遅めの日がずっと先でも、2 倍の日数で切る")
    func cappedWhenPessimisticIsFarAway() {
        let band = ForecastBandBuilder.band(
            for: range(optimisticWeeklyKg: -0.875, pessimisticWeeklyKg: -0.01, earliestDays: 8, expectedDays: 10, latestDays: 700),
            startKg: 70,
            goalWeightKg: 69,
            calendar: calendar
        )
        #expect(band.last?.date == day(20))
    }

    @Test("増量の目標でも、目標を越えたら目標に止める")
    func gainingBand() {
        // 60 kg → 61 kg。早めは 1 日 0.125 kg 増（8 日）、遅めは 1 日 1/14 kg 増（14 日）
        let band = ForecastBandBuilder.band(
            for: range(optimisticWeeklyKg: 0.875, pessimisticWeeklyKg: 0.5, earliestDays: 8, expectedDays: 10, latestDays: 14),
            startKg: 60,
            goalWeightKg: 61,
            calendar: calendar
        )
        #expect(isApproximately(band[1].lowerKg, 60.5))
        #expect(isApproximately(band[1].upperKg, 60.875))
        #expect(band.allSatisfy { $0.upperKg <= 61 + 1e-9 })
        #expect(band.allSatisfy { $0.lowerKg <= $0.upperKg })
    }

    @Test("まん中の見込みが今日なら、帯はない")
    func emptyWhenExpectedIsToday() {
        let band = ForecastBandBuilder.band(
            for: range(optimisticWeeklyKg: -0.875, pessimisticWeeklyKg: -0.5, earliestDays: 0, expectedDays: 0, latestDays: 0),
            startKg: 70,
            goalWeightKg: 69,
            calendar: calendar
        )
        #expect(band.isEmpty)
    }
}
