import Foundation

/// ヘルスケアに登録されているプロフィールの情報（HealthKit の型を Logic に持ち込まないための「値の型」）。
///
/// どれも、登録されていない・読み取りを許可されていないときは nil です。
nonisolated struct HealthProfileHints: Equatable, Sendable {
    /// いちばん新しい身長の記録（cm）
    var heightCm: Double?
    /// 生まれた年（西暦）
    var birthYear: Int?
    /// 性別（ヘルスケアで「男性」「女性」以外・未設定なら nil）
    var sex: BiologicalSex?
}

/// 初回設定の入力欄に、前もって入れておく値。nil の項目は入力欄をそのままにします。
nonisolated struct HealthProfilePrefill: Equatable, Sendable {
    var heightCm: Double?
    var birthYear: Int?
    var sex: BiologicalSex?

    /// 引き継げる項目が 1 つもないか
    var isEmpty: Bool { heightCm == nil && birthYear == nil && sex == nil }
}

/// ヘルスケアの情報のうち、初回設定の入力欄に入れてよいものを選びます。
///
/// 入力欄で受け付けない値（身長が 100〜250 cm の外、選べる生まれ年の外）は引き継がず、利用者に入力してもらいます。
/// 身長は入力欄と同じく小数第 1 位に丸めます。
nonisolated enum HealthProfilePrefiller {
    static func prefill(from hints: HealthProfileHints, today: Date, calendar: Calendar = .current) -> HealthProfilePrefill {
        var result = HealthProfilePrefill()

        if let heightCm = hints.heightCm {
            let rounded = (heightCm * 10).rounded() / 10
            if ProfileInputValidator.validHeightRangeCm.contains(rounded) {
                result.heightCm = rounded
            }
        }

        if let birthYear = hints.birthYear,
           ProfileInputValidator.selectableBirthYears(on: today, calendar: calendar).contains(birthYear) {
            result.birthYear = birthYear
        }

        result.sex = hints.sex
        return result
    }
}
