import Foundation

/// 入力欄の文字列を体重（kg）に変換し、ありえない値をはじくロジック。
///
/// 画面（SwiftUI）にも保存（SwiftData）にも依存しない純粋なロジックなので、単体テストで確かめやすくなっています。
/// `nonisolated` は「メインスレッド専用にしない」という印です（このプロジェクトは既定でメインスレッド専用のため）。
nonisolated enum WeightInputParser {
    /// 受け付ける体重の範囲（kg）。打ち間違い（例: 6.5 や 650）を防ぐための目安です。
    static let validRangeKg: ClosedRange<Double> = 20...300

    enum ParseError: Error, Equatable {
        /// 空欄
        case empty
        /// 数字として読めない
        case notANumber
        /// 範囲外
        case outOfRange
    }

    /// 文字列を体重（kg）に変換します。
    ///
    /// - 前後の空白は無視します。
    /// - 小数点は「.」と「,」のどちらでも受け付けます（地域設定によってキーボードが「,」を出すため）。
    /// - 全角数字（例: ６５．４）も受け付けます。
    /// - 小数第 1 位に四捨五入します（体重計の表示に合わせる）。
    static func parse(_ text: String) -> Result<Double, ParseError> {
        let halfwidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let normalized = halfwidth
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard !normalized.isEmpty else { return .failure(.empty) }
        guard let value = Double(normalized), value.isFinite else { return .failure(.notANumber) }

        let rounded = (value * 10).rounded() / 10
        guard validRangeKg.contains(rounded) else { return .failure(.outOfRange) }
        return .success(rounded)
    }
}
