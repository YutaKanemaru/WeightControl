import Foundation
import Testing
@testable import WeightControlApp

/// BMI の計算（BodyMetrics）と、目標体重の BMI の判定（GoalBMIAdvisor）のテスト。
/// 身長は 160 cm を基準にしています（BMI 18.5 ＝ 47.36 kg、BMI 22 ＝ 56.32 kg、BMI 25 ＝ 64.0 kg）。
struct GoalBMIAdvisorTests {
    private let heightCm = 160.0

    private func verdict(target: Double, current: Double?) -> GoalBMIVerdict? {
        GoalBMIAdvisor.advice(targetWeightKg: target, currentWeightKg: current, heightCm: heightCm)?.verdict
    }

    // MARK: - BodyMetrics

    @Test("ふつうの範囲の体重（0.1 kg 単位）と標準体重")
    func normalRange() {
        #expect(BodyMetrics.minimumNormalWeightKg(heightCm: 160) == 47.4)
        #expect(BodyMetrics.maximumNormalWeightKg(heightCm: 160) == 63.9)
        #expect(BodyMetrics.standardWeightKg(heightCm: 160) == 56.3)
        // 170 cm：18.5 → 53.465 kg（切り上げて 53.5）、25 → 72.25 kg（72.2 までが 25 未満）
        #expect(BodyMetrics.minimumNormalWeightKg(heightCm: 170) == 53.5)
        #expect(BodyMetrics.maximumNormalWeightKg(heightCm: 170) == 72.2)
    }

    @Test("丸めた範囲の端は、必ずふつうの範囲に入る")
    func roundedEdgesStayNormal() {
        for heightCm in stride(from: 140.0, through: 200.0, by: 0.5) {
            let minKg = BodyMetrics.minimumNormalWeightKg(heightCm: heightCm)
            let maxKg = BodyMetrics.maximumNormalWeightKg(heightCm: heightCm)
            #expect(BodyMetrics.band(forBMI: BodyMetrics.bmi(weightKg: minKg, heightCm: heightCm)) == .normal)
            #expect(BodyMetrics.band(forBMI: BodyMetrics.bmi(weightKg: maxKg, heightCm: heightCm)) == .normal)
            // 0.1 kg 外側は、ふつうの範囲の外
            #expect(BodyMetrics.band(forBMI: BodyMetrics.bmi(weightKg: minKg - 0.1, heightCm: heightCm)) == .low)
            #expect(BodyMetrics.band(forBMI: BodyMetrics.bmi(weightKg: maxKg + 0.1, heightCm: heightCm)) == .high)
        }
    }

    @Test("BMI の区分の境目：18.5 ちょうどと 25 ちょうど")
    func bandBoundaries() {
        #expect(BodyMetrics.band(forBMI: 18.49) == .low)
        #expect(BodyMetrics.band(forBMI: 18.5) == .normal)
        #expect(BodyMetrics.band(forBMI: 24.99) == .normal)
        #expect(BodyMetrics.band(forBMI: 25.0) == .high)
    }

    // MARK: - 判定

    @Test("身長か目標体重がなければ判定しない")
    func needsInput() {
        #expect(GoalBMIAdvisor.advice(targetWeightKg: 55, currentWeightKg: 60, heightCm: nil) == nil)
        #expect(GoalBMIAdvisor.advice(targetWeightKg: 55, currentWeightKg: 60, heightCm: 0) == nil)
        #expect(GoalBMIAdvisor.advice(targetWeightKg: nil, currentWeightKg: 60, heightCm: 160) == nil)
    }

    @Test("ふつうの範囲の目標")
    func normalGoal() throws {
        let advice = try #require(GoalBMIAdvisor.advice(targetWeightKg: 56.32, currentWeightKg: 60, heightCm: 160))
        #expect(advice.verdict == .normal)
        #expect(advice.goalBand == .normal)
        #expect(isApproximately(advice.goalBMI, 22, tolerance: 1e-6))
        let currentBMI = try #require(advice.currentBMI)
        #expect(isApproximately(currentBMI, 60 / 2.56, tolerance: 1e-6))
        #expect(advice.normalRangeKg == 47.4...63.9)
        #expect(advice.standardWeightKg == 56.3)
        #expect(advice.needsHomeAttention == false)
    }

    @Test("BMI 18.5 未満へ減らす目標は注意（BMI 18.5 の体重を提案）")
    func belowNormalWhenLosing() throws {
        #expect(verdict(target: 45, current: 52) == .belowNormal(suggestedWeightKg: 47.4))
        // 記録がなくても、目標の BMI だけで注意する
        #expect(verdict(target: 45, current: nil) == .belowNormal(suggestedWeightKg: 47.4))
        // いまも低めで、キープ（差 0.1 kg 以内）も注意
        #expect(verdict(target: 45, current: 45.1) == .belowNormal(suggestedWeightKg: 47.4))
        let advice = try #require(GoalBMIAdvisor.advice(targetWeightKg: 45, currentWeightKg: 52, heightCm: 160))
        #expect(advice.needsHomeAttention)
    }

    @Test("低めの体重から増やす目標は、注意ではなく補足")
    func gainingTowardNormal() throws {
        #expect(verdict(target: 46, current: 44) == .gainingTowardNormal(minimumNormalWeightKg: 47.4))
        // 差が 0.1 kg 以内なら「キープ」なので注意、超えたら「増やす」
        #expect(verdict(target: 45.15, current: 45.1) == .belowNormal(suggestedWeightKg: 47.4))
        #expect(verdict(target: 45.3, current: 45.1) == .gainingTowardNormal(minimumNormalWeightKg: 47.4))
        let advice = try #require(GoalBMIAdvisor.advice(targetWeightKg: 46, currentWeightKg: 44, heightCm: 160))
        #expect(advice.needsHomeAttention == false)
    }

    @Test("BMI 25 以上で減らす目標は「最初の一歩」：5〜10% 減を示す")
    func firstStep() throws {
        // 80 kg → 5% 減 76.0 kg、10% 減 72.0 kg。目標 70 kg（BMI 27.3）は 5% 減より大きいのでボタンを出す
        #expect(verdict(target: 70, current: 80) == .firstStep(fivePercentWeightKg: 76, tenPercentWeightKg: 72, firstStepWeightKg: 76))
        // 目標 78 kg は 5% 減より小さいので、ボタンは出さない
        #expect(verdict(target: 78, current: 80) == .firstStep(fivePercentWeightKg: 76, tenPercentWeightKg: 72, firstStepWeightKg: nil))
        // 5% 減ちょうどもボタンなし
        #expect(verdict(target: 76, current: 80) == .firstStep(fivePercentWeightKg: 76, tenPercentWeightKg: 72, firstStepWeightKg: nil))
        let advice = try #require(GoalBMIAdvisor.advice(targetWeightKg: 70, currentWeightKg: 80, heightCm: 160))
        #expect(advice.needsHomeAttention == false)
    }

    @Test("5% 減・10% 減は 0.1 kg 単位に四捨五入")
    func stepRounding() {
        // 83.3 kg × 0.95 = 79.135 → 79.1、× 0.9 = 74.97 → 75.0
        #expect(verdict(target: 70, current: 83.3) == .firstStep(fivePercentWeightKg: 79.1, tenPercentWeightKg: 75.0, firstStepWeightKg: 79.1))
    }

    @Test("BMI 25 以上へ増やす目標は注意（ホームにも出す）")
    func aboveNormalWhenGaining() throws {
        #expect(verdict(target: 66, current: 60) == .aboveNormal(maximumNormalWeightKg: 63.9, isGaining: true))
        let advice = try #require(GoalBMIAdvisor.advice(targetWeightKg: 66, currentWeightKg: 60, heightCm: 160))
        #expect(advice.needsHomeAttention)
    }

    @Test("BMI 25 以上のキープや、記録がないときは注意だけ（ホームには出さない）")
    func aboveNormalOther() throws {
        #expect(verdict(target: 70, current: 70) == .aboveNormal(maximumNormalWeightKg: 63.9, isGaining: false))
        #expect(verdict(target: 70, current: nil) == .aboveNormal(maximumNormalWeightKg: 63.9, isGaining: false))
        let advice = try #require(GoalBMIAdvisor.advice(targetWeightKg: 70, currentWeightKg: nil, heightCm: 160))
        #expect(advice.currentBMI == nil)
        #expect(advice.needsHomeAttention == false)
    }

    @Test("BMI ちょうど 25 の目標は「高め」")
    func exactlyTwentyFive() {
        // 160 cm で 64.0 kg は BMI 25.0
        #expect(verdict(target: 64.0, current: 60) == .aboveNormal(maximumNormalWeightKg: 63.9, isGaining: true))
        #expect(verdict(target: 63.9, current: 60) == .normal)
    }
}
