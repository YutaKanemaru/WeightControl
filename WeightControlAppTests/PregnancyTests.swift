import Foundation
import Testing
@testable import WeightControlApp

/// 妊娠中モードの計算のテスト。決まりは docs/PREGNANCY_MODE.md。
///
/// よく使う例：身長 160 cm・妊娠前 52 kg（BMI 20.3 →「ふつう」、目安 10〜13 kg）。
/// 出産予定日を基準日の 140 日後にすると、基準日はちょうど妊娠 20 週 0 日になります。
struct GestationalAgeCalculatorTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int, hour: Int = 0) -> Date { TestCalendar.day(n, hour: hour) }

    @Test("予定日まで 140 日 → 20 週 0 日（妊娠中期）")
    func ageFromDueDate() {
        let age = GestationalAgeCalculator.age(dueDate: day(140), on: day(0, hour: 15), calendar: calendar)
        #expect(age.totalDays == 140)
        #expect(age.weeks == 20)
        #expect(age.days == 0)
        #expect(age.trimester == .middle)
    }

    @Test("予定日の当日は 40 週 0 日、すぎたら 40 週より後")
    func ageAroundDueDate() {
        #expect(GestationalAgeCalculator.age(dueDate: day(0), on: day(0), calendar: calendar).totalDays == 280)
        let after = GestationalAgeCalculator.age(dueDate: day(0), on: day(10), calendar: calendar)
        #expect(after.weeks == 41)
        #expect(after.days == 3)
        #expect(after.trimester == .late)
    }

    @Test("初期・中期・後期の区切り（13 週 6 日まで初期、14 週から中期、28 週から後期）")
    func trimesterBoundaries() {
        #expect(GestationalAge(totalDays: 0).trimester == .early)
        #expect(GestationalAge(totalDays: 97).trimester == .early)
        #expect(GestationalAge(totalDays: 98).trimester == .middle)
        #expect(GestationalAge(totalDays: 195).trimester == .middle)
        #expect(GestationalAge(totalDays: 196).trimester == .late)
    }

    @Test("予定日より 280 日以上前は 0 週 0 日として表示する")
    func beforeStart() {
        let age = GestationalAgeCalculator.age(dueDate: day(300), on: day(0), calendar: calendar)
        #expect(age.totalDays == -20)
        #expect(age.weeks == 0)
        #expect(age.days == 0)
        #expect(age.trimester == .early)
    }

    @Test("「今日が 20 週 3 日」から予定日を出す（137 日後）")
    func dueDateFromWeeks() {
        #expect(GestationalAgeCalculator.dueDate(weeks: 20, days: 3, on: day(0, hour: 9), calendar: calendar) == day(137))
        // 戻すと同じ週数になる
        let due = GestationalAgeCalculator.dueDate(weeks: 8, days: 2, on: day(0), calendar: calendar)
        let age = GestationalAgeCalculator.age(dueDate: due, on: day(0), calendar: calendar)
        #expect(age.weeks == 8 && age.days == 2)
    }

    @Test("妊娠 0 週 0 日の日は予定日の 280 日前")
    func startDate() {
        #expect(GestationalAgeCalculator.startDate(dueDate: day(280), calendar: calendar) == day(0))
    }
}

struct PregnancyWeightGainGuideTests {
    @Test("妊娠前の BMI で 4 つに分ける（2021 年の目安）")
    func generalRanges() {
        // 160 cm：BMI 18.5 = 47.36 kg、25 = 64 kg、30 = 76.8 kg
        #expect(target(weightKg: 47.0) == .general(PregnancyGainRange(lowKg: 12, highKg: 15), bodyType: .low))
        #expect(target(weightKg: 52.0) == .general(PregnancyGainRange(lowKg: 10, highKg: 13), bodyType: .normal))
        #expect(target(weightKg: 64.0) == .general(PregnancyGainRange(lowKg: 7, highKg: 10), bodyType: .high))
        #expect(target(weightKg: 76.8) == .needsDoctor(.veryHighBMI))
    }

    @Test("区切りの BMI ちょうどは上の区分")
    func boundaries() {
        #expect(PrePregnancyBodyType.classify(bmi: 18.49) == .low)
        #expect(PrePregnancyBodyType.classify(bmi: 18.5) == .normal)
        #expect(PrePregnancyBodyType.classify(bmi: 24.99) == .normal)
        #expect(PrePregnancyBodyType.classify(bmi: 25.0) == .high)
        #expect(PrePregnancyBodyType.classify(bmi: 29.99) == .high)
        #expect(PrePregnancyBodyType.classify(bmi: 30.0) == .veryHigh)
    }

    @Test("赤ちゃんが 2 人以上なら、一般的な目安は出さない")
    func multiple() {
        #expect(target(weightKg: 52, isMultiple: true) == .needsDoctor(.multiple))
    }

    @Test("医師の目安を入れたら、いつもそちらを優先する")
    func customRangeWins() {
        #expect(target(weightKg: 52, low: 8, high: 11) == .custom(PregnancyGainRange(lowKg: 8, highKg: 11)))
        #expect(target(weightKg: 52, isMultiple: true, low: 16, high: 20) == .custom(PregnancyGainRange(lowKg: 16, highKg: 20)))
        #expect(target(weightKg: 80, high: 5) == .custom(PregnancyGainRange(lowKg: 0, highKg: 5)))
    }

    @Test("医師の目安がまちがっていたら使わない")
    func invalidCustomIgnored() {
        #expect(target(weightKg: 52, low: 12, high: 9) == .general(PregnancyGainRange(lowKg: 10, highKg: 13), bodyType: .normal))
    }

    @Test("医師の目安の入力のチェック")
    func validation() {
        #expect(PregnancyWeightGainGuide.validateCustomRange(lowKg: 5, highKg: 8) == nil)
        #expect(PregnancyWeightGainGuide.validateCustomRange(lowKg: nil, highKg: 5) == nil)
        #expect(PregnancyWeightGainGuide.validateCustomRange(lowKg: 0, highKg: 30) == nil)
        #expect(PregnancyWeightGainGuide.validateCustomRange(lowKg: nil, highKg: 31) == .outOfRange)
        #expect(PregnancyWeightGainGuide.validateCustomRange(lowKg: -1, highKg: 5) == .outOfRange)
        #expect(PregnancyWeightGainGuide.validateCustomRange(lowKg: 8, highKg: 5) == .lowAboveHigh)
    }

    private func target(weightKg: Double, isMultiple: Bool = false, low: Double? = nil, high: Double? = nil) -> PregnancyGainTarget {
        PregnancyWeightGainGuide.target(
            prePregnancyWeightKg: weightKg, heightCm: 160, isMultiple: isMultiple, customLowKg: low, customHighKg: high
        )
    }
}

struct PregnancyBandBuilderTests {
    private let calendar = TestCalendar.utc
    private let normal = PregnancyGainRange(lowKg: 10, highKg: 13)

    @Test("初期は下の端 0 kg、上の端は 13 週で +2 kg")
    func earlyBand() {
        #expect(PregnancyBandBuilder.band(atDay: 0, range: normal) == PregnancyBandValue(lowerGainKg: 0, upperGainKg: 0))
        let mid = PregnancyBandBuilder.band(atDay: 45, range: normal)
        #expect(mid.lowerGainKg == 0)
        #expect(isApproximately(mid.upperGainKg, 2.0 * 45 / 91))
        #expect(PregnancyBandBuilder.band(atDay: 91, range: normal) == PregnancyBandValue(lowerGainKg: 0, upperGainKg: 2))
    }

    @Test("13 週から 40 週の合計までまっすぐ（docs の表：20 週 +2.6〜4.9、28 週 +5.6〜8.1、40 週 +10〜13）")
    func laterBand() {
        let week20 = PregnancyBandBuilder.band(atDay: 140, range: normal)
        #expect(isApproximately(week20.lowerGainKg, 10.0 * 49 / 189))
        #expect(isApproximately(week20.upperGainKg, 2 + 11.0 * 49 / 189))
        #expect(isApproximately(week20.lowerGainKg, 2.59, tolerance: 0.01))
        #expect(isApproximately(week20.upperGainKg, 4.85, tolerance: 0.01))

        let week28 = PregnancyBandBuilder.band(atDay: 196, range: normal)
        #expect(isApproximately(week28.lowerGainKg, 5.56, tolerance: 0.01))
        #expect(isApproximately(week28.upperGainKg, 8.11, tolerance: 0.01))

        #expect(PregnancyBandBuilder.band(atDay: 280, range: normal) == PregnancyBandValue(lowerGainKg: 10, upperGainKg: 13))
    }

    @Test("40 週より後は合計のまま、0 週より前は 0")
    func clamped() {
        #expect(PregnancyBandBuilder.band(atDay: 300, range: normal) == PregnancyBandValue(lowerGainKg: 10, upperGainKg: 13))
        #expect(PregnancyBandBuilder.band(atDay: -7, range: normal) == PregnancyBandValue(lowerGainKg: 0, upperGainKg: 0))
    }

    @Test("合計の上の値が 2 kg より小さいときは、初期の上の端もそこまで")
    func smallCustomRange() {
        let small = PregnancyGainRange(lowKg: 0, highKg: 1.5)
        #expect(PregnancyBandBuilder.band(atDay: 91, range: small).upperGainKg == 1.5)
        #expect(PregnancyBandBuilder.band(atDay: 200, range: small) == PregnancyBandValue(lowerGainKg: 0, upperGainKg: 1.5))
    }

    @Test("グラフの点は 0 週から 40 週まで 1 週ごと（41 点）で、体重そのもの")
    func chartPoints() {
        let due = TestCalendar.day(280)
        let points = PregnancyBandBuilder.chartPoints(dueDate: due, prePregnancyWeightKg: 52, range: normal, calendar: calendar)
        #expect(points.count == 41)
        #expect(points.first == PregnancyBandPoint(date: TestCalendar.day(0), lowerKg: 52, upperKg: 52))
        #expect(points[13] == PregnancyBandPoint(date: TestCalendar.day(91), lowerKg: 52, upperKg: 54))
        #expect(points.last == PregnancyBandPoint(date: due, lowerKg: 62, upperKg: 65))
    }
}

struct PregnancyAdvisorTests {
    private let calendar = TestCalendar.utc
    private func day(_ n: Int, hour: Int = 0) -> Date { TestCalendar.day(n, hour: hour) }

    /// -20〜0 日目の毎日、`weight(n)` kg（n は日）
    private func daily(_ weight: (Int) -> Double, from first: Int = -20, through last: Int = 0) -> [WeightPoint] {
        (first...last).map { WeightPoint(date: day($0, hour: 7), weightKg: weight($0)) }
    }

    /// 予定日 140 日後（今日 20 週 0 日）、160 cm・妊娠前 52 kg（目安 10〜13 kg、今日の帯 +2.59〜4.85 kg）
    private func evaluate(
        _ points: [WeightPoint],
        dueIn days: Int = 140,
        isMultiple: Bool = false,
        customLow: Double? = nil,
        customHigh: Double? = nil
    ) -> PregnancyDashboard {
        PregnancyAdvisor.evaluate(
            points: points,
            dueDate: day(days),
            prePregnancyWeightKg: 52,
            heightCm: 160,
            isMultiple: isMultiple,
            customLowKg: customLow,
            customHighKg: customHigh,
            now: day(0, hour: 20),
            calendar: calendar
        )
    }

    @Test("帯の中：+4.0 kg（今日の帯 +2.59〜4.85 kg）")
    func within() throws {
        let result = evaluate(daily { _ in 56.0 })
        #expect(result.status == .withinRange)
        #expect(result.age.weeks == 20)
        #expect(result.latestWeightKg == 56.0)
        #expect(isApproximately(try #require(result.latestGainKg), 4.0))
        #expect(isApproximately(try #require(result.currentWeightKg), 56.0))
        #expect(result.target == .general(PregnancyGainRange(lowKg: 10, highKg: 13), bodyType: .normal))
        #expect(result.bandPoints.count == 41)
        #expect(!result.hasFewRecentRecords)
        #expect(!result.showsRapidGainNote)
    }

    @Test("帯より多め・少なめ")
    func aboveAndBelow() {
        #expect(evaluate(daily { _ in 57.5 }).status == .aboveRange)
        #expect(evaluate(daily { _ in 54.0 }).status == .belowRange)
    }

    @Test("初期（13 週まで）は「少なめ」と言わない。多めは言う")
    func earlyNeverBelow() {
        // 予定日 250 日後 → 今日は 30 日目（4 週 2 日）、帯の上の端は +0.66 kg
        let lower = evaluate(daily { _ in 51.0 }, dueIn: 250)
        #expect(lower.age.trimester == .early)
        #expect(lower.status == .withinRange)
        #expect(evaluate(daily { _ in 54.5 }, dueIn: 250).status == .aboveRange)
    }

    @Test("1 日だけ重い日があっても、直線の値で判定する")
    func usesTrendNotSingleDay() {
        let points = daily { $0 == 0 ? 58.0 : 56.0 }
        let result = evaluate(points)
        // 大きな数字は最新の記録から
        #expect(result.latestGainKg == 6.0)
        // 判定は直線の今日の値（約 56.4 kg、+4.4 kg）なので帯の中
        #expect(result.status == .withinRange)
    }

    @Test("妊娠が始まる前の記録だけなら「記録なし」")
    func noRecords() {
        #expect(evaluate([]).status == .noRecords)
        // 予定日 140 日後 → 妊娠 0 週は -140 日目
        let beforeStart = [WeightPoint(date: day(-150), weightKg: 52)]
        let result = evaluate(beforeStart)
        #expect(result.status == .noRecords)
        #expect(result.latestGainKg == nil)
    }

    @Test("赤ちゃんが 2 人以上・医師の目安なし → 一般的な帯は出さない")
    func noGuide() {
        let result = evaluate(daily { _ in 56.0 }, isMultiple: true)
        #expect(result.status == .noGuide(.multiple))
        #expect(result.bandPoints.isEmpty)
        #expect(result.bandToday == nil)
    }

    @Test("医師の目安を入れたら、その帯で判定する")
    func customRange() throws {
        // 合計 0〜5 kg：20 週の帯は上の端 2 + 3 × 49/189 = 2.78 kg → +4.0 kg は多め
        let result = evaluate(daily { _ in 56.0 }, customHigh: 5)
        #expect(result.target == .custom(PregnancyGainRange(lowKg: 0, highKg: 5)))
        #expect(isApproximately(try #require(result.bandToday?.upperGainKg), 2 + 3.0 * 49 / 189))
        #expect(result.status == .aboveRange)
    }

    @Test("急な増え方：1 週間で +1 kg 以上のペースが 2 週間以上続いたら")
    func rapidGain() {
        #expect(evaluate(daily { 56.0 + Double($0) * 1.1 / 7 }).showsRapidGainNote)
        #expect(!evaluate(daily { 56.0 + Double($0) * 0.5 / 7 }).showsRapidGainNote)
        // 記録が 7 日に足りないときは出さない
        #expect(!evaluate(daily({ 56.0 + Double($0) * 1.5 / 7 }, from: -5)).showsRapidGainNote)
        // 7 日あっても、期間が 2 週間に足りないときは出さない
        #expect(!evaluate(daily({ 56.0 + Double($0) * 1.5 / 7 }, from: -10)).showsRapidGainNote)
    }

    @Test("直近 14 日の記録の日数（未来の日付と 14 日より前は数えない）")
    func recentDays() {
        let points = [
            WeightPoint(date: day(0, hour: 7), weightKg: 56),
            WeightPoint(date: day(0, hour: 21), weightKg: 56),
            WeightPoint(date: day(-13), weightKg: 56),
            WeightPoint(date: day(-14), weightKg: 56),
            WeightPoint(date: day(1), weightKg: 56),
        ]
        #expect(PregnancyAdvisor.recentRecordedDays(points: points, now: day(0, hour: 22), calendar: calendar) == 2)
        #expect(evaluate(points).hasFewRecentRecords)
    }

    @Test("出産予定日から 2 週間たったら「続けますか？」")
    func checkIn() {
        #expect(evaluate([], dueIn: -14).isPastDueCheckIn)
        #expect(!evaluate([], dueIn: -13).isPastDueCheckIn)
        #expect(!evaluate([]).isPastDueCheckIn)
    }

    @Test("妊娠前の体重の候補：妊娠 0 週より前の 30 日の、1 日ごとの平均の平均")
    func prePregnancySuggestion() {
        // 予定日 280 日後 → 妊娠 0 週は 0 日目
        let points = [
            WeightPoint(date: day(-31), weightKg: 40),  // 30 日より前なので使わない
            WeightPoint(date: day(-30), weightKg: 50),
            WeightPoint(date: day(-1, hour: 7), weightKg: 52),
            WeightPoint(date: day(-1, hour: 21), weightKg: 54),  // 同じ日は平均して 53
            WeightPoint(date: day(0), weightKg: 60),  // 妊娠が始まってからなので使わない
        ]
        #expect(PregnancyAdvisor.prePregnancyWeightSuggestion(points: points, dueDate: day(280), calendar: calendar) == 51.5)
        #expect(PregnancyAdvisor.prePregnancyWeightSuggestion(points: [], dueDate: day(280), calendar: calendar) == nil)
    }
}

struct PregnancyModeStateTests {
    private func day(_ n: Int) -> Date { TestCalendar.day(n) }

    private func state(
        isFemale: Bool = true,
        hasActivePlan: Bool = false,
        lastEndedAt: Date? = nil,
        goalStartDate: Date? = nil,
        resumedEndedAt: Date? = nil
    ) -> PregnancyModeState {
        PregnancyWeightGainGuide.modeState(
            isFemale: isFemale, hasActivePlan: hasActivePlan, lastEndedAt: lastEndedAt,
            goalStartDate: goalStartDate, resumedEndedAt: resumedEndedAt
        )
    }

    @Test("女性でモード中なら active。女性でなければいつも off")
    func active() {
        #expect(state(hasActivePlan: true) == .active)
        #expect(state(isFemale: false, hasActivePlan: true) == .off)
        #expect(state() == .off)
    }

    @Test("終えたあと、前の目標はモードより前に決めたものなら一時停止")
    func pausedAfterEnd() {
        #expect(state(lastEndedAt: day(10), goalStartDate: day(-100)) == .goalPausedAfterPregnancy)
        #expect(!PregnancyModeState.goalPausedAfterPregnancy.usesGoal)
    }

    @Test("終えたあとに新しい目標を決めたら、ふだんどおり")
    func newGoalAfterEnd() {
        #expect(state(lastEndedAt: day(10), goalStartDate: day(11)) == .off)
    }

    @Test("「前の目標に戻す」を押したら、ふだんどおり。次のモードを終えたら、また一時停止")
    func resumed() {
        #expect(state(lastEndedAt: day(10), goalStartDate: day(-100), resumedEndedAt: day(10)) == .off)
        #expect(state(lastEndedAt: day(400), goalStartDate: day(-100), resumedEndedAt: day(10)) == .goalPausedAfterPregnancy)
    }

    @Test("目標がなければ、終えたあとはふだんどおり")
    func noGoal() {
        #expect(state(lastEndedAt: day(10)) == .off)
    }
}

struct PregnancyGainTextTests {
    @Test("医師の目安の入力欄の読み取り")
    func parse() {
        #expect(PregnancyWeightGainGuide.parseGainText("") == .empty)
        #expect(PregnancyWeightGainGuide.parseGainText("  ") == .empty)
        #expect(PregnancyWeightGainGuide.parseGainText("10") == .value(10))
        #expect(PregnancyWeightGainGuide.parseGainText("１０，５") == .value(10.5))
        #expect(PregnancyWeightGainGuide.parseGainText("7.04") == .value(7.0))
        #expect(PregnancyWeightGainGuide.parseGainText("abc") == .invalid)
    }
}
