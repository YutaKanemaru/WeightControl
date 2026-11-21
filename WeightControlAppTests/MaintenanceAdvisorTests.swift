import Foundation
import Testing
@testable import WeightControlApp

/// リバウンド抑制モード（MaintenanceAdvisor）のテスト。決まりは docs/MAINTENANCE_MODE.md。
///
/// 体重のデータは「60 kg が 14 日 → 63 kg が 7 日 → 60 kg が 21 日」の形をよく使います。
/// このとき、今の体重の目安（直近 21 日の直線の値）は 16 日目に範囲（58.5〜61.5 kg）の上に出て、
/// 26 日目に範囲に戻ります（値は Python で同じ計算をして確かめたものです）。
struct MaintenanceAdvisorTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int, hour: Int = 0) -> Date { TestCalendar.day(n, hour: hour) }

    /// 中心 60 kg・±1.5 kg（58.5〜61.5 kg）
    private let range = MaintenanceAdvisor.range(centerKg: 60, halfWidthKg: 1.5, heightCm: nil)

    /// 60 kg が 14 日 → 63 kg が 7 日 → 60 kg が 21 日（0〜41 日目）。`through` 日目までを返す。
    private func stepPoints(through last: Int = 41) -> [WeightPoint] {
        (0...last).map { n in
            WeightPoint(date: day(n), weightKg: (14...20).contains(n) ? 63.0 : 60.0)
        }
    }

    private func evaluate(_ points: [WeightPoint], start: Int = 0, now: Int) throws -> MaintenanceResult {
        try #require(MaintenanceAdvisor.evaluate(points: points, range: range, startDate: day(start), now: day(now, hour: 12), calendar: calendar))
    }

    // MARK: - 範囲

    @Test("範囲は中心 ± 幅")
    func basicRange() {
        #expect(range == MaintenanceRange(centerKg: 60, lowerKg: 58.5, upperKg: 61.5, isLowerRaisedForBMI: false))
        #expect(range.contains(58.5))
        #expect(range.contains(61.5))
        #expect(!range.contains(61.51))
        #expect(!range.contains(58.49))
    }

    @Test("下の端は BMI 18.5 の体重より下げない（160 cm → 47.4 kg）")
    func lowerEdgeRaisedForBMI() {
        let raised = MaintenanceAdvisor.range(centerKg: 48.5, halfWidthKg: 1.5, heightCm: 160)
        #expect(raised.lowerKg == 47.4)
        #expect(raised.upperKg == 50.0)
        #expect(raised.isLowerRaisedForBMI)

        // 中心がもともと BMI 18.5 未満なら、下の端は中心まで
        let belowNormal = MaintenanceAdvisor.range(centerKg: 46, halfWidthKg: 1.5, heightCm: 160)
        #expect(belowNormal.lowerKg == 46)
        #expect(belowNormal.isLowerRaisedForBMI)

        // 下の端が BMI 18.5 より上なら、そのまま
        let normal = MaintenanceAdvisor.range(centerKg: 55, halfWidthKg: 1.5, heightCm: 160)
        #expect(normal.lowerKg == 53.5)
        #expect(!normal.isLowerRaisedForBMI)
    }

    @Test("設定から始めるときの中心は 0.1 kg 単位に丸める")
    func roundedCenter() {
        #expect(MaintenanceAdvisor.roundedCenterKg(62.34) == 62.3)
        #expect(MaintenanceAdvisor.roundedCenterKg(62.36) == 62.4)
    }

    // MARK: - 状態

    @Test("範囲の外：上・下とその差")
    func outside() {
        guard case .above(let up) = MaintenanceAdvisor.status(currentKg: 62.0, dailyChangeKg: 0, range: range) else {
            Issue.record("above のはず")
            return
        }
        #expect(isApproximately(up, 0.5))
        guard case .below(let down) = MaintenanceAdvisor.status(currentKg: 58.0, dailyChangeKg: 0, range: range) else {
            Issue.record("below のはず")
            return
        }
        #expect(isApproximately(down, 0.5))
    }

    @Test("範囲の中で、14 日以内に端に届くペースなら「そろそろ端」")
    func nearEdge() {
        // 上の端まで 1.0 kg、1 日 0.1 kg → 10 日
        #expect(MaintenanceAdvisor.status(currentKg: 60.5, dailyChangeKg: 0.1, range: range) == .nearEdge(drift: .up, daysUntilExit: 10))
        // 下の端まで 0.5 kg、1 日 −0.2 kg → 2.5 日 → 3 日
        #expect(MaintenanceAdvisor.status(currentKg: 59.0, dailyChangeKg: -0.2, range: range) == .nearEdge(drift: .down, daysUntilExit: 3))
        // 1 日 0.05 kg なら 20 日かかるので「範囲の中」
        #expect(MaintenanceAdvisor.status(currentKg: 60.5, dailyChangeKg: 0.05, range: range) == .inRange)
        // 横ばい・ペースを信じにくい（nil）ときは「範囲の中」
        #expect(MaintenanceAdvisor.status(currentKg: 61.4, dailyChangeKg: 0.0001, range: range) == .inRange)
        #expect(MaintenanceAdvisor.status(currentKg: 61.4, dailyChangeKg: nil, range: range) == .inRange)
    }

    @Test("カロリーの目安：範囲の中は維持（0）、上なら −0.25 %／週、下なら ＋0.25 %／週")
    func plannedChange() {
        #expect(MaintenanceAdvisor.plannedWeeklyChangeKg(status: .inRange, currentKg: 60) == 0)
        #expect(MaintenanceAdvisor.plannedWeeklyChangeKg(status: .nearEdge(drift: .up, daysUntilExit: 3), currentKg: 60) == 0)
        #expect(isApproximately(MaintenanceAdvisor.plannedWeeklyChangeKg(status: .above(byKg: 0.5), currentKg: 62), -0.155))
        #expect(isApproximately(MaintenanceAdvisor.plannedWeeklyChangeKg(status: .below(byKg: 0.5), currentKg: 58), 0.145))
    }

    @Test("目標に届いた：±0.1 kg 以内か、目標を通りこしたとき")
    func goalAchieved() {
        #expect(MaintenanceAdvisor.isGoalAchieved(startKg: 65, currentKg: 60.05, targetKg: 60))
        #expect(MaintenanceAdvisor.isGoalAchieved(startKg: 65, currentKg: 59.4, targetKg: 60))
        #expect(!MaintenanceAdvisor.isGoalAchieved(startKg: 65, currentKg: 60.3, targetKg: 60))
        // 増やす目標
        #expect(MaintenanceAdvisor.isGoalAchieved(startKg: 50, currentKg: 52.3, targetKg: 52))
        #expect(!MaintenanceAdvisor.isGoalAchieved(startKg: 50, currentKg: 51.5, targetKg: 52))
        // キープが目標なら ±0.1 kg 以内のときだけ
        #expect(!MaintenanceAdvisor.isGoalAchieved(startKg: 60, currentKg: 59.5, targetKg: 60))
    }

    // MARK: - まとめて判定・日数

    @Test("範囲に戻ってからの日数を数える（26 日目に戻った → 41 日目は 16 日）")
    func daysInRangeAfterReturn() throws {
        let result = try evaluate(stepPoints(), now: 41)
        #expect(result.status == .inRange)
        #expect(isApproximately(result.currentWeightKg, 60, tolerance: 1e-6))
        #expect(result.daysInRange == 16)
        #expect(result.daysAboveRange == 0)
        #expect(result.plannedWeeklyChangeKg == 0)
    }

    @Test("始めた日より前は数えない（30 日目に始めた → 41 日目は 12 日）")
    func daysInRangeFromStart() throws {
        #expect(try evaluate(stepPoints(), start: 30, now: 41).daysInRange == 12)
    }

    @Test("上に出ているあいだ：上に出てからの日数と、範囲に戻す向きのカロリー")
    func aboveRange() throws {
        let result = try evaluate(stepPoints(through: 20), now: 20)
        guard case .above(let byKg) = result.status else {
            Issue.record("above のはず: \(result.status)")
            return
        }
        #expect(isApproximately(byKg, 1.409091, tolerance: 0.001))
        // 16 日目に上に出たので、16〜20 日目の 5 日
        #expect(result.daysAboveRange == 5)
        #expect(result.daysInRange == 0)
        #expect(isApproximately(result.plannedWeeklyChangeKg, -62.909091 * 0.0025, tolerance: 0.0001))
        #expect(!result.suggestsNewGoal)
    }

    @Test("上がりはじめ（14 日目）は「そろそろ端」：あと 11 日ほどで上に出る")
    func risingNearEdge() throws {
        let result = try evaluate(stepPoints(through: 14), now: 14)
        #expect(result.status == .nearEdge(drift: .up, daysUntilExit: 11))
        #expect(result.daysInRange == 15)
    }

    @Test("下がりつづけている（34 日目）は「そろそろ端」：あと 4 日ほどで下に出る")
    func fallingNearEdge() throws {
        #expect(try evaluate(stepPoints(through: 34), now: 34).status == .nearEdge(drift: .down, daysUntilExit: 4))
    }

    @Test("上に出たまま 4 週間たったら、新しい目標を決めることもすすめる")
    func suggestsNewGoal() throws {
        let points = (0...40).map { WeightPoint(date: day($0), weightKg: 63) }
        let result = try evaluate(points, now: 40)
        #expect(result.daysAboveRange == 41)
        #expect(result.suggestsNewGoal)
    }

    @Test("記録がなければ判定しない")
    func noRecords() {
        #expect(MaintenanceAdvisor.evaluate(points: [], range: range, startDate: day(0), now: day(0), calendar: calendar) == nil)
    }

    // MARK: - 出た・戻った

    @Test("範囲から出た日・戻った日だけ知らせる")
    func crossings() {
        let daily = WeightTrendCalculator.dailyAverages(stepPoints(), calendar: calendar)
        func crossing(_ n: Int, start: Int = 0) -> MaintenanceAdvisor.Crossing? {
            MaintenanceAdvisor.crossing(on: day(n), daily: daily, range: range, startDate: day(start), calendar: calendar)
        }
        #expect(crossing(15) == nil)
        #expect(crossing(16) == .left(.up))
        #expect(crossing(20) == nil)
        #expect(crossing(26) == .returned)
        #expect(crossing(27) == nil)
        // 始めた日より前は見ない
        #expect(crossing(16, start: 20) == nil)
        // 記録のない日は nil
        #expect(crossing(50) == nil)
    }

    @Test("ある日までの記録で見た目安（その日より後の記録は使わない）")
    func estimateAsOf() throws {
        let daily = WeightTrendCalculator.dailyAverages(stepPoints(), calendar: calendar)
        #expect(isApproximately(try #require(MaintenanceAdvisor.weightEstimate(asOf: day(13), daily: daily, calendar: calendar)), 60, tolerance: 1e-6))
        #expect(isApproximately(try #require(MaintenanceAdvisor.weightEstimate(asOf: day(16), daily: daily, calendar: calendar)), 61.764706, tolerance: 0.001))
        #expect(MaintenanceAdvisor.weightEstimate(asOf: day(-1), daily: daily, calendar: calendar) == nil)
    }

    // MARK: - メッセージ

    @Test("ほめるメッセージ：範囲の中は日数をほめ、外でも責めない")
    func praise() {
        func message(_ status: MaintenanceStatus, days: Int = 0) -> PraiseMessage {
            MaintenanceAdvisor.praise(for: MaintenanceResult(
                range: range, currentWeightKg: 60, status: status,
                daysInRange: days, daysAboveRange: 0, plannedWeeklyChangeKg: 0
            ))
        }
        #expect(message(.inRange, days: 30).kind == .maintenanceKept(days: 30))
        #expect(message(.inRange, days: 30).text.contains("30"))
        #expect(message(.inRange, days: 3).kind == .maintenanceKept(days: 3))
        #expect(message(.above(byKg: 0.5)).kind == .maintenanceDrift)
        #expect(message(.nearEdge(drift: .down, daysUntilExit: 3)).kind == .maintenanceDrift)
    }

    // MARK: - ホームとのつなぎ（HomeDashboardBuilder）

    private func dashboard(_ points: [WeightPoint], goal: DashboardGoal, includesPro: Bool, now: Int) -> HomeDashboard {
        HomeDashboardBuilder.build(
            points: points,
            profile: DashboardProfile(heightCm: 170, birthYear: 1990, sex: .male, activityLevel: .sedentary),
            goal: goal,
            foods: [],
            includesPro: includesPro,
            now: day(now, hour: 12),
            calendar: calendar
        )
    }

    @Test("目標に届くと isGoalAchieved（無料版でも。Pro の案内に使う）")
    func homeGoalAchieved() {
        let points = (0..<10).map { WeightPoint(date: day($0), weightKg: 60) }
        let goal = DashboardGoal(targetWeightKg: 60, deadline: day(30), startWeightKg: 65)
        #expect(dashboard(points, goal: goal, includesPro: false, now: 9).isGoalAchieved)
        #expect(dashboard(points, goal: goal, includesPro: true, now: 9).isGoalAchieved)
        #expect(dashboard(points, goal: goal, includesPro: true, now: 9).maintenance == nil)
    }

    @Test("Pro でモード中なら、予測などの代わりに範囲の判定を出す。無料版ではモードの情報を使わない")
    func homeMaintenanceGating() {
        let points = stepPoints(through: 20)
        var goal = DashboardGoal(targetWeightKg: 60, deadline: day(0), startWeightKg: 65, startDate: day(0))
        goal.maintenanceStartDate = day(0)

        let pro = dashboard(points, goal: goal, includesPro: true, now: 20)
        #expect(pro.maintenance != nil)
        #expect(pro.forecast == nil)
        #expect(pro.safety == nil)
        #expect(!pro.isGoalAchieved)
        // 上に出ているので、維持カロリーより少なめ
        #expect((pro.intake?.dailyBalanceKcal ?? 0) < 0)

        let free = dashboard(points, goal: goal, includesPro: false, now: 20)
        #expect(free.maintenance == nil)
        #expect(free.forecast != nil)
    }
}
