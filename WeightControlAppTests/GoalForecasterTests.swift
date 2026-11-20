import Foundation
import Testing
@testable import WeightControlApp

/// 予測が出なかったときにテストを止めるためのエラー
private struct ForecastNotAvailable: Error {}

/// 目標までの予測（GoalForecaster）と予測線（ForecastLineBuilder）のテスト
struct GoalForecasterTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    /// 80 kg から毎日 0.1 kg ずつ減る記録を `days` 日分
    private func steadyLoss(days: Int) -> [WeightPoint] {
        (0..<days).map { WeightPoint(date: day($0), weightKg: 80 - 0.1 * Double($0)) }
    }

    private func forecast(
        _ points: [WeightPoint],
        goal: Double,
        deadline: Date? = nil,
        now: Date? = nil
    ) -> GoalForecastResult {
        GoalForecaster.forecast(
            points: points,
            goalWeightKg: goal,
            deadline: deadline,
            now: now ?? points.map(\.date).max() ?? day(0),
            calendar: calendar
        )
    }

    private func available(_ result: GoalForecastResult) throws -> GoalForecast {
        guard case .available(let forecast) = result else {
            Issue.record("予測が出ていない: \(result)")
            throw ForecastNotAvailable()
        }
        return forecast
    }

    // MARK: - 記録日数

    @Test("記録がなければ予測できない")
    func noData() {
        #expect(forecast([], goal: 70) == .insufficientData(recordedDays: 0, requiredDays: 3))
    }

    @Test("記録が 2 日だけなら、まだ予測できない（あと 1 日）")
    func twoDaysIsNotEnough() {
        #expect(forecast(steadyLoss(days: 2), goal: 70) == .insufficientData(recordedDays: 2, requiredDays: 3))
    }

    @Test("記録が 3 日あれば予測を出す")
    func threeDaysIsEnough() throws {
        let result = try available(forecast(steadyLoss(days: 3), goal: 70))
        #expect(result.recordedDays == 3)
        #expect(isApproximately(result.weeklyChangeKg, -0.7))
    }

    @Test("同じ日に何回測っても 1 日として数える")
    func countsDaysNotEntries() {
        let points = (0..<2).flatMap { n in
            [WeightPoint(date: day(n), weightKg: 70), WeightPoint(date: day(n).addingTimeInterval(3_600), weightKg: 70)]
        }
        #expect(forecast(points, goal: 65) == .insufficientData(recordedDays: 2, requiredDays: 3))
    }

    @Test("21 日より前の記録は数えない")
    func ignoresOldRecords() {
        // 100 日前に 10 日分 + 最近 2 日分
        let old = (0..<10).map { WeightPoint(date: day($0), weightKg: 80) }
        let recent = (100..<102).map { WeightPoint(date: day($0), weightKg: 78) }
        #expect(forecast(old + recent, goal: 70) == .insufficientData(recordedDays: 2, requiredDays: 3))
    }

    @Test("3〜6 日は「精度が低め」、7 日以上は「信頼できる」")
    func confidenceByRecordedDays() throws {
        #expect(try available(forecast(steadyLoss(days: 3), goal: 70)).confidence == .low)
        #expect(try available(forecast(steadyLoss(days: 6), goal: 70)).confidence == .low)
        #expect(try available(forecast(steadyLoss(days: 7), goal: 70)).confidence == .reliable)
    }

    // MARK: - ペースと到達日

    @Test("毎日 0.1 kg 減っていれば、ペースは約 −0.7 kg/週")
    func weeklyPaceOfSteadyLoss() throws {
        let result = try available(forecast(steadyLoss(days: 60), goal: 70))
        #expect(result.recordedDays == 21)
        #expect(isApproximately(result.weeklyChangeKg, -0.7, tolerance: 1e-6))
        #expect(result.latestDate == day(59))
        // 測った体重に直線を引くので、今の体重の目安は遅れなく最新の体重（74.1 kg）と一致する
        #expect(isApproximately(result.currentWeightKg, 74.1, tolerance: 1e-6))
    }

    @Test("今のペースが続いたときの到達日を出す")
    func predictsReachDate() throws {
        // 計算上：今の体重の目安 74.1 kg、−0.1 kg/日 → 41 日後（59 + 41 = 100 日目）
        let result = try available(forecast(steadyLoss(days: 60), goal: 70))
        #expect(result.outcome == .willReach(on: day(100)))
    }

    @Test("ばらつきがあっても、直線の傾きからペースを出せる")
    func paceFromNoisyData() throws {
        // 毎日 0.05 kg 減りつつ、1 日おきに ±0.5 kg ぶれる
        let points = (0..<42).map { n in
            WeightPoint(date: day(n), weightKg: 80 - 0.05 * Double(n) + (n.isMultiple(of: 2) ? -0.5 : 0.5))
        }
        let result = try available(forecast(points, goal: 75))
        #expect(isApproximately(result.weeklyChangeKg, -0.35, tolerance: 0.01))
        guard case .willReach = result.outcome else {
            Issue.record("到達日が出ていない: \(result.outcome)")
            return
        }
    }

    @Test("今の体重の目安が目標 ±0.1 kg 以内なら「届いた」")
    func reachedGoal() throws {
        let points = (0..<10).map { WeightPoint(date: day($0), weightKg: 65.05) }
        let result = try available(forecast(points, goal: 65.0, deadline: day(30)))
        #expect(result.outcome == .reached)
        #expect(result.deadlineStatus == .onTrack)
    }

    @Test("体重が横ばいなら「近づいていない」")
    func flatTrend() throws {
        let points = (0..<20).map { WeightPoint(date: day($0), weightKg: 70) }
        let result = try available(forecast(points, goal: 65))
        #expect(isApproximately(result.weeklyChangeKg, 0))
        #expect(result.outcome == .notApproaching)
    }

    @Test("減らしたいのに増えているなら「近づいていない」")
    func wrongDirection() throws {
        let points = (0..<20).map { WeightPoint(date: day($0), weightKg: 70 + 0.05 * Double($0)) }
        let result = try available(forecast(points, goal: 65))
        #expect(result.weeklyChangeKg > 0)
        #expect(result.outcome == .notApproaching)
    }

    @Test("増やしたいときは、増えるペースで到達日を出す")
    func weightGainGoal() throws {
        let points = (0..<30).map { WeightPoint(date: day($0), weightKg: 50 + 0.03 * Double($0)) }
        let result = try available(forecast(points, goal: 52))
        #expect(result.weeklyChangeKg > 0)
        guard case .willReach(let date) = result.outcome else {
            Issue.record("到達日が出ていない: \(result.outcome)")
            return
        }
        #expect(date > day(29))
    }

    @Test("2 年以上先になる予測は出さない")
    func beyondHorizon() throws {
        // 毎日 0.002 kg（0.014 kg/週）しか減らない → 10 kg に 13 年以上
        let points = (0..<30).map { WeightPoint(date: day($0), weightKg: 80 - 0.002 * Double($0)) }
        let result = try available(forecast(points, goal: 70))
        #expect(result.outcome == .notApproaching)
    }

    // MARK: - 期限

    @Test("期限を決めていなければ、期限の判定はない")
    func noDeadline() throws {
        #expect(try available(forecast(steadyLoss(days: 60), goal: 70)).deadlineStatus == nil)
    }

    @Test("到達日が期限より前なら、間に合う")
    func onTrackForDeadline() throws {
        let result = try available(forecast(steadyLoss(days: 60), goal: 70, deadline: day(120)))
        #expect(result.deadlineStatus == .onTrack)
    }

    @Test("到達日が期限ちょうどでも、間に合う")
    func reachOnDeadlineDay() throws {
        let result = try available(forecast(steadyLoss(days: 60), goal: 70, deadline: day(100)))
        #expect(result.deadlineStatus == .onTrack)
    }

    @Test("到達日が期限より後なら、必要なペースを返す")
    func behindDeadline() throws {
        // 59 日目時点で今の体重の目安 74.1 kg、期限まで 31 日 → 約 −0.93 kg/週 必要
        let result = try available(forecast(steadyLoss(days: 60), goal: 70, deadline: day(90)))
        guard case .behind(let required) = result.deadlineStatus else {
            Issue.record("期限に間に合う判定になっている: \(String(describing: result.deadlineStatus))")
            return
        }
        #expect(isApproximately(required, (70 - result.currentWeightKg) / (31.0 / 7)))
        #expect(isApproximately(required, -0.93, tolerance: 0.01))
    }

    @Test("期限が過ぎていれば「過ぎた」")
    func deadlinePassed() throws {
        let result = try available(forecast(steadyLoss(days: 60), goal: 70, deadline: day(50)))
        #expect(result.deadlineStatus == .passed)
    }

    // MARK: - 予測線（グラフの点線）

    @Test("予測線は今の体重の目安から始まり、到達日にちょうど目標体重で終わる")
    func projectionEndsAtGoal() throws {
        let result = try available(forecast(steadyLoss(days: 60), goal: 70))
        let line = ForecastLineBuilder.projection(for: result, goalWeightKg: 70, deadline: nil, calendar: calendar)

        let first = try #require(line.first)
        let last = try #require(line.last)
        #expect(first == WeightPoint(date: day(59), weightKg: result.currentWeightKg))
        #expect(last == WeightPoint(date: day(100), weightKg: 70))
        // 7 日ごとの点（59, 66, …, 94）＋最後の点（100）
        #expect(line.count == 7)
        #expect(line[1].date == day(66))
        #expect(line.map(\.date) == line.map(\.date).sorted())
        // 途中の点は目標体重を下回らない
        #expect(line.allSatisfy { $0.weightKg >= 70 })
    }

    @Test("近づいていないときは、期限まで今の傾向を描く")
    func projectionWhenNotApproaching() throws {
        let points = (0..<20).map { WeightPoint(date: day($0), weightKg: 70) }
        let result = try available(forecast(points, goal: 65, deadline: day(40)))
        let line = ForecastLineBuilder.projection(for: result, goalWeightKg: 65, deadline: day(40), calendar: calendar)
        #expect(line.first?.date == day(19))
        #expect(line.last?.date == day(40))
        #expect(line.allSatisfy { isApproximately($0.weightKg, 70) })
    }

    @Test("近づいておらず期限もないときは、4 週間先まで描く")
    func projectionWithoutDeadline() throws {
        let points = (0..<20).map { WeightPoint(date: day($0), weightKg: 70) }
        let result = try available(forecast(points, goal: 65))
        let line = ForecastLineBuilder.projection(for: result, goalWeightKg: 65, deadline: nil, calendar: calendar)
        #expect(line.last?.date == day(19 + 28))
    }

    @Test("もう届いていれば予測線はいらない")
    func noProjectionWhenReached() throws {
        let points = (0..<10).map { WeightPoint(date: day($0), weightKg: 65) }
        let result = try available(forecast(points, goal: 65))
        #expect(ForecastLineBuilder.projection(for: result, goalWeightKg: 65, deadline: nil, calendar: calendar).isEmpty)
    }

    @Test("予測線：点の値は直線の上にある")
    func projectionValues() {
        let line = ForecastLineBuilder.projection(
            startDate: day(0), startKg: 70, weeklyChangeKg: -0.7,
            goalWeightKg: nil, endDate: day(14), calendar: calendar
        )
        #expect(line.map(\.date) == [day(0), day(7), day(14)])
        #expect(isApproximately(line[1].weightKg, 69.3))
        #expect(isApproximately(line[2].weightKg, 68.6))
    }

    @Test("これまでの直線は、いちばん古い記録の日から今の体重の目安まで")
    func fittedLineSpansWindow() throws {
        // 30 日分の記録のうち、直線に使うのは直近 21 日（9〜29 日目）
        let estimate = try #require(GoalForecaster.paceEstimate(points: steadyLoss(days: 30), calendar: calendar))
        let line = ForecastLineBuilder.fittedLine(for: estimate, calendar: calendar)
        #expect(line.count == 2)
        #expect(line[0].date == day(9))
        #expect(line[1].date == day(29))
        #expect(isApproximately(line[0].weightKg, 80 - 0.9))
        #expect(isApproximately(line[1].weightKg, estimate.currentWeightKg))
        #expect(isApproximately(line[1].weightKg, 80 - 2.9))
    }

    @Test("必要なペースの線は、今から期限の日の目標体重まで")
    func requiredPaceLine() {
        let line = ForecastLineBuilder.requiredPace(
            startDate: day(0), startKg: 70, goalWeightKg: 68, deadline: day(28), calendar: calendar
        )
        #expect(line == [WeightPoint(date: day(0), weightKg: 70), WeightPoint(date: day(28), weightKg: 68)])
        #expect(ForecastLineBuilder.requiredPace(
            startDate: day(10), startKg: 70, goalWeightKg: 68, deadline: day(5), calendar: calendar
        ).isEmpty)
    }
}
