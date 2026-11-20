import Testing
@testable import WeightControlApp

/// 体重入力の「−」「＋」ボタン（WeightEntryStepper）のテスト
struct WeightEntryStepperTests {

    @Test("入力欄の初期値は小数第 1 位までの文字")
    func textForWeight() {
        #expect(WeightEntryStepper.text(for: 64.5) == "64.5")
        #expect(WeightEntryStepper.text(for: 70) == "70.0")
        #expect(WeightEntryStepper.text(for: 64.46) == "64.5")
    }

    @Test("＋で 0.1 kg、−で 0.1 kg 動く")
    func stepsByTenth() {
        #expect(WeightEntryStepper.adjusted("64.5", steps: 1, fallbackKg: nil) == "64.6")
        #expect(WeightEntryStepper.adjusted("64.5", steps: -1, fallbackKg: nil) == "64.4")
        #expect(WeightEntryStepper.adjusted("64.5", steps: -3, fallbackKg: nil) == "64.2")
    }

    @Test("何度押しても小数の誤差が出ない")
    func noFloatingPointDrift() {
        var text = "64.0"
        for _ in 0..<7 {
            text = WeightEntryStepper.adjusted(text, steps: 1, fallbackKg: nil) ?? text
        }
        #expect(text == "64.7")
    }

    @Test("カンマや全角で入力されていても動かせる")
    func acceptsParserFormats() {
        #expect(WeightEntryStepper.adjusted("64,5", steps: 1, fallbackKg: nil) == "64.6")
        #expect(WeightEntryStepper.adjusted("６４．５", steps: -1, fallbackKg: nil) == "64.4")
    }

    @Test("入力欄が空なら前回の体重から動かす。前回もなければ動かさない")
    func fallsBackToPreviousWeight() {
        #expect(WeightEntryStepper.adjusted("", steps: 1, fallbackKg: 64.5) == "64.6")
        #expect(WeightEntryStepper.adjusted("abc", steps: -1, fallbackKg: 64.5) == "64.4")
        #expect(WeightEntryStepper.adjusted("", steps: 1, fallbackKg: nil) == nil)
    }

    @Test("受け付ける範囲（20〜300 kg）からはみ出さない")
    func clampsToValidRange() {
        #expect(WeightEntryStepper.adjusted("20.0", steps: -1, fallbackKg: nil) == "20.0")
        #expect(WeightEntryStepper.adjusted("300.0", steps: 1, fallbackKg: nil) == "300.0")
    }
}
