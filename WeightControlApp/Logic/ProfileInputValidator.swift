import Foundation

/// プロフィール・目標の入力欄の値を変換・チェックするロジック。
///
/// 画面（SwiftUI）にも保存（SwiftData）にも依存しない純粋な関数なので、単体テストで確かめられます。
/// 目標体重の数字の読み取りは、体重入力と同じ `WeightInputParser` を使います。
nonisolated enum ProfileInputValidator {
    /// 受け付ける身長の範囲（cm）。打ち間違い（例: 17 や 1700）を防ぐための目安です。
    static let validHeightRangeCm: ClosedRange<Double> = 100...250
    /// 受け付ける年齢の範囲（歳）。カロリー計算式が想定している大人の年齢を目安にしています。
    static let validAgeRange: ClosedRange<Int> = 15...100

    enum HeightError: Error, Equatable {
        case empty
        case notANumber
        case outOfRange
    }

    enum DeadlineError: Error, Equatable {
        /// 今日か、それより前の日付
        case notInFuture
    }

    /// 文字列を身長（cm）に変換します。
    ///
    /// - 前後の空白は無視し、小数点は「.」と「,」のどちらでも受け付けます。
    /// - 全角数字（例: １７０）も受け付けます。
    /// - 小数第 1 位に四捨五入します。
    static func parseHeightCm(_ text: String) -> Result<Double, HeightError> {
        let halfwidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let normalized = halfwidth
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard !normalized.isEmpty else { return .failure(.empty) }
        guard let value = Double(normalized), value.isFinite else { return .failure(.notANumber) }

        let rounded = (value * 10).rounded() / 10
        guard validHeightRangeCm.contains(rounded) else { return .failure(.outOfRange) }
        return .success(rounded)
    }

    /// 生まれ年と今日の日付から、今年なる年齢（歳）を返します。
    ///
    /// 誕生日までは保存していないので「今年の誕生日を迎えた後の年齢」です（最大 1 歳のずれは計算上ほぼ影響しません）。
    static func age(birthYear: Int, on date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: date) - birthYear
    }

    /// 選べる生まれ年の一覧（新しい順）。年齢が `validAgeRange` に入る年だけを返します。
    static func selectableBirthYears(on date: Date, calendar: Calendar = .current) -> [Int] {
        let currentYear = calendar.component(.year, from: date)
        let newest = currentYear - validAgeRange.lowerBound
        let oldest = currentYear - validAgeRange.upperBound
        return Array((oldest...newest).reversed())
    }

    /// 期限が「明日以降」になっているかを確かめます。
    static func validateDeadline(_ deadline: Date, today: Date, calendar: Calendar = .current) -> Result<Date, DeadlineError> {
        let startOfToday = calendar.startOfDay(for: today)
        let startOfDeadline = calendar.startOfDay(for: deadline)
        guard startOfDeadline > startOfToday else { return .failure(.notInFuture) }
        return .success(deadline)
    }
}
