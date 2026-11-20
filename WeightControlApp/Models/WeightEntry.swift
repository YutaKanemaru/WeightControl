import Foundation
import SwiftData

/// 体重の記録 1 件分。
///
/// `@Model` を付けると、SwiftData がこのクラスを「端末内のデータベースに保存できる形」として扱います。
/// プロパティ（`date`, `weightKg`）がそのままデータベースの列になります。
/// ここには「保存する形」だけを書き、計算は `Logic/` に置きます。
@Model
final class WeightEntry {
    /// 測った日時
    var date: Date
    /// 体重（kg）
    var weightKg: Double

    init(date: Date, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}
