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

    @Test("① 順調：期限より前（27 日後）に届く見込み")
    func onTrack() throws {
        let result = try dashboard(.onTrack)
        #expect(isApproximately(try #require(result.currentWeightKg), 70.032468, tolerance: 0.001))
        #expect(result.streakDays == 28)

        let forecast = try available(result.forecast)
        #expect(forecast.confidence == .reliable)
        #expect(forecast.recordedDays == 21)
        #expect(isApproximately(forecast.weeklyChangeKg, -0.527273, tolerance: 0.001))
        #expect(forecast.outcome == .willReach(on: day(27)))
        #expect(forecast.deadlineStatus == .onTrack)

        #expect(result.forecastLine.count == 5)
        #expect(result.forecastLine.last == WeightPoint(date: day(27), weightKg: 68.0))

        guard case .safe(let required)? = result.safety else {
            Issue.record("safe のはず: \(String(describing: result.safety))")
            return
        }
        #expect(isApproximately(required, -0.203247, tolerance: 0.001))

        let intake = try #require(result.intake)
        #expect(isApproximately(intake.tdeeKcal, 2190.1339, tolerance: 0.01))
        #expect(isApproximately(intake.targetKcal, 1981.0801, tolerance: 0.01))
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

    @Test("② 横ばい：目標に向かう流れが見えず、食べ物ヒント（シュークリーム 1 個分）が出る")
    func plateau() throws {
        let result = try dashboard(.plateau)
        #expect(isApproximately(try #require(result.currentWeightKg), 69.961039, tolerance: 0.001))
        #expect(result.streakDays == 28)

        let forecast = try available(result.forecast)
        #expect(forecast.confidence == .reliable)
        #expect(isApproximately(forecast.weeklyChangeKg, -0.027273, tolerance: 0.001))
        #expect(forecast.outcome == .notApproaching)
        guard case .behind(let needed)? = forecast.deadlineStatus else {
            Issue.record("behind のはず: \(String(describing: forecast.deadlineStatus))")
            return
        }
        #expect(isApproximately(needed, -0.231061, tolerance: 0.001))

        // 予測線は期限（120 日後）まで、ほぼ横ばい
        #expect(result.forecastLine.last?.date == day(120))
        #expect(isApproximately(try #require(result.forecastLine.last?.weightKg), 69.49351, tolerance: 0.001))

        let intake = try #require(result.intake)
        #expect(isApproximately(intake.tdeeKcal, 1621.3325, tolerance: 0.01))
        #expect(isApproximately(intake.targetKcal, 1383.6701, tolerance: 0.01))
        #expect(!intake.isRaisedToMinimum)

        #expect(isApproximately(try #require(result.overPlanKcalPerDay), 209.6104, tolerance: 0.01))
        guard case .over(let food, let count, _)? = result.calorieHint else {
            Issue.record("食べ物ヒントが出るはず: \(String(describing: result.calorieHint))")
            return
        }
        #expect(food.id == "cream_puff")
        #expect(count == 1)

        #expect(result.praise.kind == .trendSteady)
    }

    // MARK: - ③ 速すぎる目標

    @Test("③ 速すぎる：修正案（77 日後・77.4 kg）が出て、カロリーは基礎代謝に合わせる")
    func tooAggressive() throws {
        let result = try dashboard(.tooAggressive)
        #expect(isApproximately(try #require(result.currentWeightKg), 80.825974, tolerance: 0.001))
        #expect(result.streakDays == 21)

        let forecast = try available(result.forecast)
        #expect(forecast.confidence == .reliable)
        #expect(forecast.recordedDays == 21)
        #expect(isApproximately(forecast.weeklyChangeKg, -0.421818, tolerance: 0.001))
        #expect(forecast.outcome == .willReach(on: day(147)))
        guard case .behind(let needed)? = forecast.deadlineStatus else {
            Issue.record("behind のはず: \(String(describing: forecast.deadlineStatus))")
            return
        }
        #expect(isApproximately(needed, -2.059394, tolerance: 0.001))

        guard case .tooAggressive(let correction)? = result.safety else {
            Issue.record("tooAggressive のはず: \(String(describing: result.safety))")
            return
        }
        #expect(isApproximately(try #require(correction.requiredWeeklyChangeKg), -2.059394, tolerance: 0.001))
        #expect(isApproximately(correction.maxWeeklyChangeKg, -0.808260, tolerance: 0.001))
        #expect(correction.suggestedDeadline == day(77))
        #expect(correction.suggestedGoalWeightKg == 77.4)

        let intake = try #require(result.intake)
        #expect(isApproximately(intake.tdeeKcal, 2078.4117, tolerance: 0.01))
        #expect(isApproximately(intake.targetKcal, 1732.0097, tolerance: 0.01))
        #expect(intake.isRaisedToMinimum)

        // 計画（上限ペース 週 −0.81 kg）より減り方がゆっくりなので、ヒントが出る
        #expect(isApproximately(try #require(result.overPlanKcalPerDay), 397.4827, tolerance: 0.01))
        guard case .over(let food, let count, _)? = result.calorieHint else {
            Issue.record("食べ物ヒントが出るはず: \(String(describing: result.calorieHint))")
            return
        }
        #expect(food.id == "french_fries")
        #expect(count == 1)

        guard case .trendTowardGoal(let change) = result.praise.kind else {
            Issue.record("trendTowardGoal のはず: \(result.praise.kind)")
            return
        }
        #expect(isApproximately(change, -0.333306, tolerance: 0.001))
    }

    // MARK: - ④ 記録が少ない

    @Test("④ 記録 10 日：予測は出る（48 日後・精度の注意なし）、食べ物ヒントは出ない（14 日未満）")
    func fewRecords() throws {
        let result = try dashboard(.fewRecords)
        #expect(isApproximately(try #require(result.currentWeightKg), 59.574545, tolerance: 0.001))
        #expect(result.streakDays == 10)

        let forecast = try available(result.forecast)
        #expect(forecast.confidence == .reliable)
        #expect(forecast.recordedDays == 10)
        #expect(isApproximately(forecast.weeklyChangeKg, -0.381818, tolerance: 0.001))
        #expect(forecast.outcome == .willReach(on: day(48)))
        #expect(forecast.deadlineStatus == .onTrack)

        guard case .safe(let required)? = result.safety else {
            Issue.record("safe のはず: \(String(describing: result.safety))")
            return
        }
        #expect(isApproximately(required, -0.200242, tolerance: 0.001))

        let intake = try #require(result.intake)
        #expect(isApproximately(intake.tdeeKcal, 1732.15, tolerance: 0.01))
        #expect(isApproximately(intake.targetKcal, 1526.1864, tolerance: 0.01))
        #expect(!intake.isRaisedToMinimum)

        #expect(result.overPlanKcalPerDay == nil)
        #expect(result.calorieHint == nil)
        #expect(result.praise.kind == .trendSteady)
    }

    // MARK: - Pro：チートデーの提案（docs/DEMO_DATA.md の 8.）

    private func proDashboard(_ scenario: DemoScenario) throws -> HomeDashboard {
        let set = scenario.dataSet(today: now, calendar: calendar)
        return HomeDashboardBuilder.build(
            points: set.points,
            profile: set.profile,
            goal: set.goal,
            foods: try FoodCatalog.loadBundledFoods(),
            includesPro: true,
            now: now,
            calendar: calendar
        )
    }

    @Test("Pro ①：予定より 0.854 kg 先に進んでいるので、チートデーを 2 日まで提案する")
    func onTrackCheatDay() throws {
        let result = try proDashboard(.onTrack)
        let suggestion = try #require(result.cheatDaySuggestion?.suggestion)
        #expect(isApproximately(suggestion.plannedWeightKg, 70.886598, tolerance: 0.001))
        #expect(isApproximately(suggestion.aheadKg, 0.854130, tolerance: 0.001))
        #expect(isApproximately(suggestion.costKgPerDay, 0.029035, tolerance: 0.0001))
        #expect(suggestion.suggestedDays == 2)
        #expect(isApproximately(suggestion.cheatDayKcal, 2190.1339, tolerance: 0.01))
        #expect(isApproximately(suggestion.regularDayKcal, 1981.0801, tolerance: 0.01))
        #expect(suggestion.selectableDates == (0..<7).map { day($0) })
        // Pro でも無料版の目安は変わらない
        let free = try dashboard(.onTrack)
        #expect(result.intake == free.intake)
        #expect(free.cheatDaySuggestion == nil)
    }

    @Test("Pro ②③：期限に間に合わないので提案しない。④：貯金 0.153 kg なので提案しない")
    func otherScenariosNoCheatDay() throws {
        #expect(try proDashboard(.plateau).cheatDaySuggestion == .notSuggested(.notOnTrack))
        #expect(try proDashboard(.tooAggressive).cheatDaySuggestion == .notSuggested(.notOnTrack))
        guard case .notSuggested(.notAheadEnough(let aheadKg))? = try proDashboard(.fewRecords).cheatDaySuggestion else {
            Issue.record("④ は notAheadEnough のはず")
            return
        }
        #expect(isApproximately(aheadKg, 0.152727, tolerance: 0.001))
    }

    // MARK: - ⑤ キープモード（Pro）

    @Test("⑤ キープモード：範囲 53.5〜56.5 kg の中だが、10 日ほどで上に出そう（そろそろ端）")
    func maintenance() throws {
        let result = try proDashboard(.maintenance)
        let keep = try #require(result.maintenance)
        #expect(keep.range == MaintenanceRange(centerKg: 55.0, lowerKg: 53.5, upperKg: 56.5, isLowerRaisedForBMI: false))
        #expect(isApproximately(keep.currentWeightKg, 56.036797, tolerance: 0.001))
        #expect(keep.status == .nearEdge(drift: .up, daysUntilExit: 10))
        // 21 日前に始めてから、ずっと範囲の中（始めた日も含めて 22 日）
        #expect(keep.daysInRange == 22)
        #expect(keep.daysAboveRange == 0)
        #expect(keep.plannedWeeklyChangeKg == 0)

        // 範囲の中なので、摂取カロリーの目安は維持カロリー（消費カロリーの目安そのまま）
        let intake = try #require(result.intake)
        #expect(isApproximately(intake.tdeeKcal, 1683.5060, tolerance: 0.01))
        #expect(isApproximately(intake.targetKcal, 1683.5060, tolerance: 0.01))

        // 上の端に向かっているので食べ物ヒント（カップ麺 1 個分）
        #expect(isApproximately(try #require(result.overPlanKcalPerDay), 348.7792, tolerance: 0.01))
        guard case .over(let food, let count, _)? = result.calorieHint else {
            Issue.record("食べ物ヒントが出るはず: \(String(describing: result.calorieHint))")
            return
        }
        #expect(food.id == "cup_noodle")
        #expect(count == 1)

        // モード中は、目標に向かうための表示は出さない
        #expect(result.forecast == nil)
        #expect(result.forecastLine.isEmpty)
        #expect(result.safety == nil)
        #expect(result.forecastRange == nil)
        #expect(result.cheatDaySuggestion == nil)
        #expect(!result.isGoalAchieved)
        #expect(result.praise.kind == .maintenanceDrift)
    }

    @Test("⑤ 無料版では、モードの情報は使わず、目標達成として Pro の案内を出す")
    func maintenanceFree() throws {
        let result = try dashboard(.maintenance)
        #expect(result.maintenance == nil)
        // 今の目安 56.04 kg は目標 55.0 kg より上なので、「届いた」にはならない（予測と安全チェックはふだんどおり）
        #expect(!result.isGoalAchieved)
        #expect(result.forecast != nil)
    }

    // MARK: - ⑥ 妊娠中モード

    @Test("⑥ 妊娠中モード：今日は 24 週 0 日、妊娠前から +4.9 kg、目安の帯（+4.07〜6.48 kg）の中")
    func pregnancy() throws {
        let set = DemoScenario.pregnancy.dataSet(today: now, calendar: calendar)
        let plan = try #require(set.pregnancy)
        #expect(plan.dueDate == day(112))
        #expect(plan.prePregnancyWeightKg == 52.0)
        #expect(DemoScenario.allCases.filter { $0 != .pregnancy }.allSatisfy { $0.dataSet(today: now, calendar: calendar).pregnancy == nil })

        let result = PregnancyAdvisor.evaluate(
            points: set.points,
            dueDate: plan.dueDate,
            prePregnancyWeightKg: plan.prePregnancyWeightKg,
            heightCm: set.profile.heightCm,
            isMultiple: false,
            customLowKg: nil,
            customHighKg: nil,
            now: now,
            calendar: calendar
        )
        #expect(result.age.weeks == 24)
        #expect(result.age.days == 0)
        #expect(result.age.trimester == .middle)
        #expect(result.target == .general(PregnancyGainRange(lowKg: 10, highKg: 13), bodyType: .normal))
        // 大きな数字は最新の記録（56.9 kg）から
        #expect(isApproximately(try #require(result.latestGainKg), 4.9, tolerance: 1e-9))
        // 判定は直近 21 日の直線の今日の値（57.13 kg、+5.13 kg）
        #expect(isApproximately(try #require(result.currentWeightKg), 57.126, tolerance: 0.001))
        let band = try #require(result.bandToday)
        #expect(isApproximately(band.lowerGainKg, 4.074, tolerance: 0.001))
        #expect(isApproximately(band.upperGainKg, 6.481, tolerance: 0.001))
        #expect(result.status == .withinRange)
        #expect(!result.showsRapidGainNote)
        #expect(!result.hasFewRecentRecords)
        #expect(!result.isPastDueCheckIn)
    }
}
