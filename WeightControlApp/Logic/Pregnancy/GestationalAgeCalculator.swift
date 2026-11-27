import Foundation

/// 妊娠の時期（初期・中期・後期）。区切りは日本の母子健康手帳などで使われるもの。
nonisolated enum PregnancyTrimester: Equatable, Sendable {
    /// 妊娠初期（0 週 0 日〜13 週 6 日）
    case early
    /// 妊娠中期（14 週 0 日〜27 週 6 日）
    case middle
    /// 妊娠後期（28 週 0 日〜）
    case late
}

/// 妊娠週数（「20 週 3 日」のような数え方）。
nonisolated struct GestationalAge: Equatable, Sendable {
    /// 妊娠 0 週 0 日から数えた日数（出産予定日が 280 日 ＝ 40 週 0 日）。予定日より前の日付を入れると負になることもある。
    var totalDays: Int

    /// 週（「20 週 3 日」の 20）。0 日未満のときは 0。
    var weeks: Int { max(totalDays, 0) / 7 }
    /// 日（「20 週 3 日」の 3）。0 日未満のときは 0。
    var days: Int { max(totalDays, 0) % 7 }

    /// 初期・中期・後期
    var trimester: PregnancyTrimester {
        switch totalDays {
        case ..<GestationalAgeCalculator.middleStartDay: .early
        case ..<GestationalAgeCalculator.lateStartDay: .middle
        default: .late
        }
    }
}

/// 出産予定日と妊娠週数の計算（docs/PREGNANCY_MODE.md）。
///
/// 出産予定日を「妊娠 40 週 0 日」（0 週 0 日から 280 日目）として、今日が何週何日かを数えます。
/// SwiftUI / SwiftData には依存しない、ただの計算です。
nonisolated enum GestationalAgeCalculator {
    /// 出産予定日の日数（40 週 0 日）
    static let dueDay = 280
    /// 妊娠中期が始まる日（14 週 0 日）
    static let middleStartDay = 14 * 7
    /// 妊娠後期が始まる日（28 週 0 日）
    static let lateStartDay = 28 * 7
    /// 「週数」から入れるときの、入れられる週の範囲（0〜41 週）
    static let enterableWeeks = 0...41

    /// `date` の日の妊娠週数。
    static func age(dueDate: Date, on date: Date, calendar: Calendar = .current) -> GestationalAge {
        let daysUntilDue = DayMath.days(from: date, to: dueDate, calendar: calendar)
        return GestationalAge(totalDays: dueDay - daysUntilDue)
    }

    /// 「今日が `weeks` 週 `days` 日」から出産予定日を出す（その日の 0 時）。
    static func dueDate(weeks: Int, days: Int, on date: Date, calendar: Calendar = .current) -> Date {
        let total = weeks * 7 + days
        return DayMath.date(byAddingDays: dueDay - total, to: date, calendar: calendar)
    }

    /// 妊娠 0 週 0 日の日（出産予定日の 280 日前、その日の 0 時）。
    static func startDate(dueDate: Date, calendar: Calendar = .current) -> Date {
        DayMath.date(byAddingDays: -dueDay, to: dueDate, calendar: calendar)
    }
}
