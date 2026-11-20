import Foundation

/// テストで共通に使う日付まわりの道具。
///
/// テストを実行する Mac のタイムゾーンによって結果が変わらないように、
/// いつも「グレゴリオ暦・UTC」のカレンダーを使います。
enum TestCalendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 基準日（2027-01-15 00:00 UTC）
    static let baseDate = Date(timeIntervalSince1970: 1_799_971_200)

    /// 基準日から `days` 日後の 0 時（UTC）。`hour` を指定するとその時刻。
    static func day(_ days: Int, hour: Int = 0) -> Date {
        baseDate.addingTimeInterval(Double(days) * 86_400 + Double(hour) * 3_600)
    }
}

/// 小数の比較用：差が `tolerance` 以下なら等しいとみなす。
func isApproximately(_ value: Double, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
    abs(value - expected) <= tolerance
}
