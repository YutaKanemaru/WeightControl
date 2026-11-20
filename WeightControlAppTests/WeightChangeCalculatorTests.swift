import Foundation
import Testing
@testable import WeightControlApp

/// 前回からの増減（WeightChangeCalculator）のテスト
struct WeightChangeCalculatorTests {

    /// 基準日から days 日後の日付を作る（テストを読みやすくするため）
    private func day(_ days: Int) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(Double(days) * 86_400)
    }

    @Test("記録がなければ空の配列")
    func emptyInput() {
        #expect(WeightChangeCalculator.changesFromPrevious([]).isEmpty)
    }

    @Test("記録が 1 件だけなら比べる相手がないので nil")
    func singleEntry() {
        let points = [WeightPoint(date: day(0), weightKg: 65)]
        #expect(WeightChangeCalculator.changesFromPrevious(points) == [nil])
    }

    @Test("新しい順に並んだ記録で、それぞれ直前の記録との差を返す")
    func newestFirst() {
        // 一覧画面と同じ「新しい順」
        let points = [
            WeightPoint(date: day(2), weightKg: 64.6),
            WeightPoint(date: day(1), weightKg: 64.9),
            WeightPoint(date: day(0), weightKg: 65.0),
        ]
        #expect(WeightChangeCalculator.changesFromPrevious(points) == [-0.3, -0.1, nil])
    }

    @Test("並び順がバラバラでも、日付で前後を判断する")
    func unsortedInput() {
        let points = [
            WeightPoint(date: day(1), weightKg: 65.2),
            WeightPoint(date: day(2), weightKg: 65.0),
            WeightPoint(date: day(0), weightKg: 65.5),
        ]
        #expect(WeightChangeCalculator.changesFromPrevious(points) == [-0.3, -0.2, nil])
    }

    @Test("小数の誤差が出ないよう 0.1 kg 単位に丸める")
    func roundsDifference() {
        let points = [
            WeightPoint(date: day(0), weightKg: 0.1 + 64.0),
            WeightPoint(date: day(1), weightKg: 64.4),
        ]
        #expect(WeightChangeCalculator.changesFromPrevious(points) == [nil, 0.3])
    }

    @Test("同じ体重なら差は 0")
    func noChange() {
        let points = [
            WeightPoint(date: day(0), weightKg: 65.0),
            WeightPoint(date: day(1), weightKg: 65.0),
        ]
        #expect(WeightChangeCalculator.changesFromPrevious(points) == [nil, 0])
    }
}
