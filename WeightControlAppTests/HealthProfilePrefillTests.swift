import Foundation
import Testing
@testable import WeightControlApp

/// ヘルスケアの身長・生まれ年・性別を初回設定に引き継ぐルール（HealthProfilePrefiller）のテスト
struct HealthProfilePrefillTests {
    private let calendar = TestCalendar.utc
    /// 基準日は 2027 年
    private let today = TestCalendar.baseDate

    @Test("登録されている値は、そのまま引き継ぐ（身長は小数第 1 位に丸める）")
    func copiesValidValues() {
        let hints = HealthProfileHints(heightCm: 171.26, birthYear: 1990, sex: .female)
        let prefill = HealthProfilePrefiller.prefill(from: hints, today: today, calendar: calendar)
        #expect(prefill == HealthProfilePrefill(heightCm: 171.3, birthYear: 1990, sex: .female))
        #expect(!prefill.isEmpty)
    }

    @Test("入力欄で受け付けない身長は引き継がない")
    func skipsHeightOutOfRange() {
        let tooShort = HealthProfilePrefiller.prefill(from: HealthProfileHints(heightCm: 45), today: today, calendar: calendar)
        let tooTall = HealthProfilePrefiller.prefill(from: HealthProfileHints(heightCm: 260), today: today, calendar: calendar)
        #expect(tooShort.heightCm == nil)
        #expect(tooTall.heightCm == nil)
    }

    @Test("選べる年齢（15〜100 歳）の外の生まれ年は引き継がない")
    func skipsBirthYearOutOfRange() {
        // 2027 年に 10 歳・105 歳
        let young = HealthProfilePrefiller.prefill(from: HealthProfileHints(birthYear: 2017), today: today, calendar: calendar)
        let old = HealthProfilePrefiller.prefill(from: HealthProfileHints(birthYear: 1922), today: today, calendar: calendar)
        #expect(young.birthYear == nil)
        #expect(old.birthYear == nil)
        // ちょうど 15 歳は OK
        let edge = HealthProfilePrefiller.prefill(from: HealthProfileHints(birthYear: 2012), today: today, calendar: calendar)
        #expect(edge.birthYear == 2012)
    }

    @Test("何も登録されていなければ空")
    func emptyWhenNothing() {
        let prefill = HealthProfilePrefiller.prefill(from: HealthProfileHints(), today: today, calendar: calendar)
        #expect(prefill.isEmpty)
    }
}
