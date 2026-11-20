import Foundation
import SwiftData

/// 体重の目標（目標体重と期限）。
///
/// アプリ内では「いまの目標」を 1 件だけ持ちます。目標を決め直したときは同じものを書き換えます。
/// 予測（フェーズ 3）や無理な目標のチェック（フェーズ 4）は、この値を Logic に渡して計算します。
@Model
final class WeightGoal {
    /// 目標体重（kg）
    var targetWeightKg: Double
    /// 期限（この日までに目標体重にしたい）
    var deadline: Date
    /// 目標を決めた日時
    var startDate: Date
    /// 目標を決めたときの体重（kg）。記録がまだなければ nil。進み具合の表示に使います。
    var startWeightKg: Double?

    init(targetWeightKg: Double, deadline: Date, startDate: Date = .now, startWeightKg: Double? = nil) {
        self.targetWeightKg = targetWeightKg
        self.deadline = deadline
        self.startDate = startDate
        self.startWeightKg = startWeightKg
    }
}
