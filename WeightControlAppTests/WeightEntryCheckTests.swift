import Foundation
import Testing
@testable import WeightControlApp

/// 体重の入力画面の確認（WeightEntryCheck）のテスト
struct WeightEntryCheckTests {

    @Test("前回と 2.0 kg 以上ちがえば差を返す（増えても減っても）")
    func largeChange() {
        #expect(WeightEntryCheck.largeChange(newKg: 60.0, previousKg: 67.0) == -7.0)
        #expect(WeightEntryCheck.largeChange(newKg: 69.5, previousKg: 67.0) == 2.5)
    }

    @Test("ちょうど 2.0 kg でも確認する（小数の誤差で漏れない）")
    func exactlyThreshold() {
        #expect(WeightEntryCheck.largeChange(newKg: 64.7, previousKg: 66.7) == -2.0)
    }

    @Test("2.0 kg より小さい差や、前回がないときは確認しない")
    func noConfirmation() {
        #expect(WeightEntryCheck.largeChange(newKg: 66.0, previousKg: 67.9) == nil)
        #expect(WeightEntryCheck.largeChange(newKg: 60.0, previousKg: nil) == nil)
    }

    @Test("同じ日の記録があるか（時刻がちがっても同じ日なら true）")
    func sameDay() {
        let calendar = TestCalendar.utc
        let existing = [TestCalendar.day(0, hour: 7), TestCalendar.day(-1, hour: 22)]
        #expect(WeightEntryCheck.hasEntry(onSameDayAs: TestCalendar.day(0, hour: 21), existingDates: existing, calendar: calendar))
        #expect(!WeightEntryCheck.hasEntry(onSameDayAs: TestCalendar.day(1, hour: 7), existingDates: existing, calendar: calendar))
        #expect(!WeightEntryCheck.hasEntry(onSameDayAs: TestCalendar.day(0), existingDates: [], calendar: calendar))
    }
}
