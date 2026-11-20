import Foundation
import Testing
@testable import WeightControlApp

/// デモデータ（DemoScenario）のテスト。
///
/// `docs/DEMO_DATA.md` に書いた「画面に出るはずの値」を、実際のロジック（HomeDashboardBuilder）で計算して確かめます。
/// ここが通っていれば、ドキュメントの期待値はアプリの計算と一致しています。
/// ロジックを変えてここが失敗したら、ドキュメントの期待値も一緒に直してください。
struct DemoScenarioTests {
    private let calendar = TestCalendar.utc
    /// 「今日」＝ 基準日の昼 12 時（アプリで読み込んだ時刻のつもり）
    private let now = TestCalendar.day(0, hour: 12)
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    private func dashboard(_ scenario: DemoScenario) throws -> HomeDashboard {
        let set = scenario.dataSet(today: now, calendar: calendar)
        return HomeDashboardBuilder.build(
            points: set.points,
            profile: set.profile,
            goal: set.goal,
            foods: try FoodCatalog.loadBundledFoods(),
            now: now,
            calendar: calendar
        )
    }

    private func available(_ result: GoalForecastResult?) throws -> GoalForecast {
        guard case .available(let forecast)? = result else {
            Issue.record("予測が出ていません: \(String(describing: result))")
            throw CancellationError()
        }
        return forecast
    }

    // MARK: - データの形

    @Test("最後の記録が今日の朝 7 時で、毎日 1 件ずつ並ぶ", arguments: DemoScenario.allCases)
    func dataShape(scenario: DemoScenario) {
        let set = scenario.dataSet(today: now, calendar: calendar)
        let count = scenario.weightsKg.count
        #expect(set.points.count == count)
        #expect(set.points.last?.date == TestCalendar.day(0, hour: 7))
        #expect(set.points.first?.date == TestCalendar.day(-(count - 1), hour: 7))
        #expect(set.points.map(\.weightKg) == scenario.weightsKg)
        #expect(set.goalStartDate == day(-(count - 1)))
        #expect(set.goal.deadline == day(scenario.goal.deadlineDaysFromToday))
        // 年齢は「年」の差だけで計算するので、いつ読み込んでも 35 歳
        #expect(CalorieCalculator.ageYears(birthYear: set.profile.birthYear, on: now, calendar: calendar) == 35)
    }

    // MARK: - ① 順調

    @Test("① 順調：期限より前（52 日後）に届く見込み")
    func onTrack() throws {
        let result = try dashboard(.onTrack)
        #expect(isApproximately(try #require(result.currentTrendKg), 70.661994, tolerance: 0.001))
        #expect(result.streakDays == 28)

        let forecast = try available(result.forecast)
        #expect(forecast.confidence == .reliable)
        #expect(forecast.recordedDays == 28)
        #expect(isApproximately(forecast.weeklyChangeKg, -0.362114, tolerance: 0.001))
        #expect(forecast.outcome == .willReach(on: day(52)))
        #expect(forecast.deadlineStatus == .onTrack)

        #expect(result.forecastLine.count == 9)
        #expect(result.forecastLine.last == WeightPoint(date: day(52), weightKg: 68.0))

        guard case .safe(let required)? = result.safety else {
            Issue.record("safe のはず: \(String(describing: result.safety))")
            return
        }
        #expect(isApproximately(required, -0.266199, tolerance: 0.001))

        let intake = try #require(result.intake)
        #expect(isApproximately(intake.tdeeKcal, 2198.79, tolerance: 0.01))
        #expect(isApproximately(intake.targetKcal, 1924.985, tolerance: 0.01))
        #expect(!intake.isRaisedToMinimum)

        // 計画より速く減っているので、食べ物ヒントは出ない
        #expect(result.overPlanKcalPerDay == nil)
        #expect(result.calorieHint == nil)

        guard case .trendTowardGoal(let change) = result.praise.kind else {
            Issue.record("trendTowardGoal のはず: \(result.praise.kind)")
            return
        }
        #expect(isApproximately(change, -0.460124, tolerance: 0.001))
    }

    // MARK: - ② 横ばい

    @Test("② 横ばい：目標に向かう流れが見えず、食べ物ヒント（ごはん 1 杯分）が出る")
    func plateau() throws {
        let result = try dashboard(.plateau)
        #expect(isApproximately(try #require(result.currentTrendKg), 69.985073, tolerance: 0.001))
        #expect(result.streakDays == 28)

        let forecast = try available(result.forecast)
        #expect(forecast.confidence == .reliable)
        #expect(isApproximately(forecast.weeklyChangeKg, -0.003230, tolerance: 0.001))
        #expect(forecast.outcome == .notApproaching)
        guard case .behind(let needed)? = forecast.deadlineStatus else {
            Issue.record("behind のはず: \(String(describing: forecast.deadlineStatus))")
            return
        }
        #expect(isApproximately(needed, -0.232463, tolerance: 0.001))

        // 予測線は期限（120 日後）まで、ほぼ横ばい
        #expect(result.forecastLine.last?.date == day(120))
        #expect(isApproximately(try #require(result.forecastLine.last?.weightKg), 69.9297, tolerance: 0.001))

        let intake = try #require(result.intake)
        #expect(isApproximately(intake.tdeeKcal, 1621.621, tolerance: 0.01))
        #expect(isApproximately(intake.targetKcal, 1382.516, tolerance: 0.01))
        #expect(!intake.isRaisedToMinimum)

        #expect(isApproximately(try #require(result.overPlanKcalPerDay), 235.782, tolerance: 0.01))
        guard case .over(let food, let count, _)? = result.calorieHint else {
            Issue.record("食べ物ヒントが出るはず: \(String(describing: result.calorieHint))")
            return
        }
        #expect(food.id == "rice")
        #expect(count == 1)

        #expect(result.praise.kind == .trendSteady)
    }

    // MARK: - ③ 速すぎる目標

    @Test("③ 速すぎる：修正案（81 日後・77.9 kg）が出て、カロリーは基礎代謝に合わせる")
    func tooAggressive() throws {
        let result = try dashboard(.tooAggressive)
        #expect(isApproximately(try #require(result.currentTrendKg), 81.297672, tolerance: 0.001))
        #expect(result.streakDays == 21)

        let forecast = try available(result.forecast)
        #expect(forecast.confidence == .reliable)
        #expect(forecast.recordedDays == 21)
        #expect(isApproximately(forecast.weeklyChangeKg, -0.254373, tolerance: 0.001))
        #expect(forecast.outcome == .willReach(on: day(256)))
        guard case .behind(let needed)? = forecast.deadlineStatus else {
            Issue.record("behind のはず: \(String(describing: forecast.deadlineStatus))")
            return
        }
        #expect(isApproximately(needed, -2.169457, tolerance: 0.001))

        guard case .tooAggressive(let correction)? = result.safety else {
            Issue.record("tooAggressive のはず: \(String(describing: result.safety))")
            return
        }
        #expect(isApproximately(try #require(correction.requiredWeeklyChangeKg), -2.169457, tolerance: 0.001))
        #expect(isApproximately(correction.maxWeeklyChangeKg, -0.812977, tolerance: 0.001))
        #expect(correction.suggestedDeadline == day(81))
        #expect(correction.suggestedGoalWeightKg == 77.9)

        let intake = try #require(result.intake)
        #expect(isApproximately(intake.tdeeKcal, 2084.072, tolerance: 0.01))
        #expect(isApproximately(intake.targetKcal, 1736.727, tolerance: 0.01))
        #expect(intake.isRaisedToMinimum)

        // 計画（上限ペース 週 −0.81 kg）より減り方がゆっくりなので、ヒントが出る
        #expect(isApproximately(try #require(result.overPlanKcalPerDay), 574.564, tolerance: 0.01))
        guard case .over(let food, let count, _)? = result.calorieHint else {
            Issue.record("食べ物ヒントが出るはず: \(String(describing: result.calorieHint))")
            return
        }
        #expect(food.id == "sake")
        #expect(count == 3)

        guard case .trendTowardGoal(let change) = result.praise.kind else {
            Issue.record("trendTowardGoal のはず: \(result.praise.kind)")
            return
        }
        #expect(isApproximately(change, -0.333306, tolerance: 0.001))
    }

    // MARK: - ④ 記録が少ない

    @Test("④ 記録 10 日：予測は「参考値」、食べ物ヒントは出ない")
    func fewRecords() throws {
        let result = try dashboard(.fewRecords)
        #expect(isApproximately(try #require(result.currentTrendKg), 59.852810, tolerance: 0.001))
        #expect(result.streakDays == 10)

        let forecast = try available(result.forecast)
        #expect(forecast.confidence == .reference)
        #expect(forecast.recordedDays == 10)
        #expect(isApproximately(forecast.weeklyChangeKg, -0.126573, tolerance: 0.001))
        #expect(forecast.outcome == .willReach(on: day(158)))
        guard case .behind(let needed)? = forecast.deadlineStatus else {
            Issue.record("behind のはず: \(String(describing: forecast.deadlineStatus))")
            return
        }
        #expect(isApproximately(needed, -0.221885, tolerance: 0.001))

        guard case .safe(let required)? = result.safety else {
            Issue.record("safe のはず: \(String(describing: result.safety))")
            return
        }
        #expect(isApproximately(required, -0.221885, tolerance: 0.001))

        let intake = try #require(result.intake)
        #expect(isApproximately(intake.tdeeKcal, 1735.976, tolerance: 0.01))
        #expect(isApproximately(intake.targetKcal, 1507.751, tolerance: 0.01))
        #expect(!intake.isRaisedToMinimum)

        #expect(result.overPlanKcalPerDay == nil)
        #expect(result.calorieHint == nil)
        #expect(result.praise.kind == .trendSteady)
    }
}
