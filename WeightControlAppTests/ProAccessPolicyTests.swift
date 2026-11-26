import Foundation
import Testing
@testable import WeightControlApp

/// Pro を使えるかどうかのルール（ProAccessPolicy）のテスト
struct ProAccessPolicyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func status(
        isPurchased: Bool = false,
        trialStart: Date? = nil,
        isDebugTrialOn: Bool = false,
        allowsDebugTrial: Bool = false,
        now: Date
    ) -> ProAccessStatus {
        ProAccessPolicy.status(
            isPurchased: isPurchased,
            trialStartDate: trialStart,
            isDebugTrialOn: isDebugTrialOn,
            allowsDebugTrial: allowsDebugTrial,
            now: now,
            calendar: calendar
        )
    }

    @Test("購入していれば、お試しやスイッチに関係なく使える")
    func purchasedIsAlwaysUnlocked() {
        let now = date(2026, 11, 21)
        #expect(status(isPurchased: true, now: now) == .purchased)
        #expect(status(isPurchased: true, trialStart: date(2026, 1, 1), now: now) == .purchased)
        #expect(status(isPurchased: true, isDebugTrialOn: true, allowsDebugTrial: true, now: now) == .purchased)
        #expect(ProAccessStatus.purchased.isUnlocked)
    }

    @Test("お試しを始めていなければ、使えず「試す」を出せる")
    func notStartedIsAvailable() {
        let result = status(now: date(2026, 11, 21))
        #expect(result == .trialAvailable)
        #expect(!result.isUnlocked)
    }

    @Test("お試しは始めた日から次の月の同じ日の 0 時まで")
    func trialLastsOneMonth() {
        let start = date(2026, 11, 21, hour: 22)
        let endsAt = date(2026, 12, 21, hour: 0)
        #expect(ProAccessPolicy.trialEndDate(startedAt: start, calendar: calendar) == endsAt)

        // 始めた日：残り 30 日
        #expect(status(trialStart: start, now: date(2026, 11, 21, hour: 23)) == .trial(endsAt: endsAt, daysLeft: 30))
        // 最後の日（12 月 20 日）の夜：残り 1 日で、まだ使える
        let lastDay = status(trialStart: start, now: date(2026, 12, 20, hour: 23))
        #expect(lastDay == .trial(endsAt: endsAt, daysLeft: 1))
        #expect(lastDay.isUnlocked)
        // 12 月 21 日の 0 時で終わる
        let ended = status(trialStart: start, now: endsAt)
        #expect(ended == .trialEnded(endedAt: endsAt))
        #expect(!ended.isUnlocked)
    }

    @Test("月末に始めても、次の月の末日までに終わる")
    func trialFromMonthEnd() {
        // 1 月 31 日 + 1 か月 = 2 月 28 日（2027 年はうるう年ではない）
        let endsAt = ProAccessPolicy.trialEndDate(startedAt: date(2027, 1, 31), calendar: calendar)
        #expect(endsAt == date(2027, 2, 28, hour: 0))
    }

    @Test("Debug ビルドでは「Pro を試す」がオンなら、お試しが終わっていても使える")
    func debugTrialUnlocksInDebugBuild() {
        let now = date(2026, 11, 21)
        #expect(status(isDebugTrialOn: true, allowsDebugTrial: true, now: now) == .debugUnlocked)
        #expect(status(trialStart: date(2026, 1, 1), isDebugTrialOn: true, allowsDebugTrial: true, now: now).isUnlocked)
        #expect(status(isDebugTrialOn: false, allowsDebugTrial: true, now: now) == .trialAvailable)
    }

    @Test("Release ビルドでは、スイッチがオンでも購入かお試しでないと使えない")
    func debugTrialIsIgnoredInReleaseBuild() {
        let now = date(2026, 11, 21)
        #expect(status(isDebugTrialOn: true, allowsDebugTrial: false, now: now) == .trialAvailable)
        let ended = status(trialStart: date(2026, 1, 1), isDebugTrialOn: true, allowsDebugTrial: false, now: now)
        #expect(!ended.isUnlocked)
    }
}
