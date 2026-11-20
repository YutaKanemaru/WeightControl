import Testing
@testable import WeightControlApp

/// 体重入力の変換・チェック（WeightInputParser）のテスト
struct WeightInputParserTests {

    @Test("ふつうの数字はそのまま kg として読める")
    func parsesPlainNumber() {
        #expect(WeightInputParser.parse("65.4") == .success(65.4))
        #expect(WeightInputParser.parse("70") == .success(70))
    }

    @Test("前後の空白は無視する")
    func trimsWhitespace() {
        #expect(WeightInputParser.parse("  65.4 \n") == .success(65.4))
    }

    @Test("小数点がカンマでも読める")
    func acceptsCommaAsDecimalSeparator() {
        #expect(WeightInputParser.parse("65,4") == .success(65.4))
    }

    @Test("全角数字でも読める")
    func acceptsFullwidthDigits() {
        #expect(WeightInputParser.parse("６５．４") == .success(65.4))
    }

    @Test("小数第 1 位に四捨五入する")
    func roundsToOneDecimal() {
        #expect(WeightInputParser.parse("65.44") == .success(65.4))
        #expect(WeightInputParser.parse("65.46") == .success(65.5))
    }

    @Test("空欄はエラー", arguments: ["", "   "])
    func rejectsEmpty(text: String) {
        #expect(WeightInputParser.parse(text) == .failure(.empty))
    }

    @Test("数字でない文字はエラー", arguments: ["abc", "65.4kg", "6..5", "nan", "inf"])
    func rejectsNonNumbers(text: String) {
        #expect(WeightInputParser.parse(text) == .failure(.notANumber))
    }

    @Test("範囲外（20〜300 kg 以外）はエラー", arguments: ["0", "-60", "6.5", "19.9", "300.1", "650"])
    func rejectsOutOfRange(text: String) {
        #expect(WeightInputParser.parse(text) == .failure(.outOfRange))
    }

    @Test("範囲の端（20 と 300）は受け付ける")
    func acceptsRangeBoundaries() {
        #expect(WeightInputParser.parse("20") == .success(20))
        #expect(WeightInputParser.parse("300") == .success(300))
    }
}
