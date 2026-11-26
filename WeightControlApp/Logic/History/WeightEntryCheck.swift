import Foundation

/// 体重の入力画面で、保存する前に確かめること（docs/WEIGHT_RECORDS.md）。
///
/// 予報は同じ日の記録を平均して 1 日 1 点にするので、何回記録しても重みは増えません。
/// ただ、打ち間違いなどの極端な数字はその日の値を動かすので、大きくちがうときだけ確認します。
nonisolated enum WeightEntryCheck {
    /// 前回の記録とこれ以上ちがえば確認する（kg）。1 日のブレ（1〜2 kg）より大きく、打ち間違いは拾える幅。
    static let largeChangeThresholdKg = 2.0

    /// 前回の記録と大きくちがうなら、その差（kg、プラスは増加）。確認しなくてよければ nil。
    static func largeChange(newKg: Double, previousKg: Double?) -> Double? {
        guard let previousKg else { return nil }
        let diff = ((newKg - previousKg) * 10).rounded() / 10
        // 小数の誤差で 1.9999999 になって確認が出ない、ということがないよう丸めてから比べる
        return abs(diff) >= largeChangeThresholdKg ? diff : nil
    }

    /// `date` と同じ日の記録が、もうあるか。
    static func hasEntry(onSameDayAs date: Date, existingDates: [Date], calendar: Calendar = .current) -> Bool {
        existingDates.contains { calendar.isDate($0, inSameDayAs: date) }
    }
}
