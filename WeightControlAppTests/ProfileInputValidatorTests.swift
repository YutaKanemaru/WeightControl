import Foundation
import Testing
@testable import WeightControlApp

/// プロフィール・目標の入力チェック（ProfileInputValidator）のテスト
struct ProfileInputValidatorTests {

    /// テストの結果が実行する国や地域で変わらないように、暦とタイムゾーンを固定する
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - 身長

    @Test("ふつうの数字はそのまま cm として読める")
    func parsesPlainHeight() {
        #expect(ProfileInputValidator.parseHeightCm("170") == .success(170))
        #expect(ProfileInputValidator.parseHeightCm("165.5") == .success(165.5))
    }

    @Test("空白・カンマ・全角数字も受け付ける")
    func acceptsLooseInput() {
        #expect(ProfileInputValidator.parseHeightCm("  170 ") == .success(170))
        #expect(ProfileInputValidator.parseHeightCm("165,5") == .success(165.5))
        #expect(ProfileInputValidator.parseHeightCm("１７０") == .success(170))
    }

    @Test("小数第 1 位に四捨五入する")
    func roundsHeight() {
        #expect(ProfileInputValidator.parseHeightCm("170.26") == .success(170.3))
    }

    @Test("空欄・数字以外・範囲外はエラー")
    func rejectsInvalidHeight() {
        #expect(ProfileInputValidator.parseHeightCm("") == .failure(.empty))
        #expect(ProfileInputValidator.parseHeightCm("abc") == .failure(.notANumber))
        #expect(ProfileInputValidator.parseHeightCm("17") == .failure(.outOfRange))
        #expect(ProfileInputValidator.parseHeightCm("1700") == .failure(.outOfRange))
    }

    @Test("範囲の端（100 cm と 250 cm）は受け付ける")
    func acceptsBoundaryHeight() {
        #expect(ProfileInputValidator.parseHeightCm("100") == .success(100))
        #expect(ProfileInputValidator.parseHeightCm("250") == .success(250))
    }

    // MARK: - 年齢

    @Test("生まれ年から今年の年齢を出す")
    func computesAge() {
        #expect(ProfileInputValidator.age(birthYear: 1990, on: date(2026, 11, 20), calendar: calendar) == 36)
        #expect(ProfileInputValidator.age(birthYear: 1990, on: date(2026, 1, 1), calendar: calendar) == 36)
    }

    @Test("選べる生まれ年は 15〜100 歳になる年だけで、新しい順")
    func selectableBirthYears() {
        let years = ProfileInputValidator.selectableBirthYears(on: date(2026, 11, 20), calendar: calendar)
        #expect(years.first == 2011)
        #expect(years.last == 1926)
        #expect(years.count == 86)
    }

    // MARK: - 期限

    @Test("期限は明日以降なら OK")
    func acceptsFutureDeadline() {
        let today = date(2026, 11, 20)
        let tomorrow = date(2026, 11, 21, hour: 0)
        #expect(ProfileInputValidator.validateDeadline(tomorrow, today: today, calendar: calendar) == .success(tomorrow))
    }

    @Test("期限が今日や過去ならエラー")
    func rejectsPastDeadline() {
        let today = date(2026, 11, 20)
        #expect(ProfileInputValidator.validateDeadline(date(2026, 11, 20, hour: 23), today: today, calendar: calendar) == .failure(.notInFuture))
        #expect(ProfileInputValidator.validateDeadline(date(2026, 1, 1), today: today, calendar: calendar) == .failure(.notInFuture))
    }
}
